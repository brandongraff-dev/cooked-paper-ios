import Foundation
import SwiftUI

/// First run, before the paywall: a new user sees their $10,000 paper balance,
/// plays a practice round, signs in (and, for a brand-new account, picks a
/// username), answers one question, picks up to three coins,
/// and buys them for real (paper trades filled at the live price on the server). Then they watch those positions
/// move. The paywall that follows is about keeping that portfolio.
///
/// `RootView` owns the `hasSeenOnboarding` flag; this view only reports completion.
struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var model = OnboardingModel()
    @State private var step: OnboardingStep = .balance
    @State private var isMovingForward = true

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.s8)

            ZStack {
                switch step {
                case .balance:
                    BalanceStep { go(to: .practice) }
                case .practice:
                    PracticeRoundStep {
                        go(to: SessionStore.shared.isSignedIn ? stepAfterSignIn : .signIn)
                    }
                case .signIn:
                    SignInView(
                        title: "Save your progress",
                        subtitle: "Sign in to get your $10,000 paper portfolio. It's saved to your account, on any device."
                    ) {
                        go(to: stepAfterSignIn)
                        Task { await PortfolioStore.shared.resetAndRebootstrap() }
                    }
                case .profile:
                    ProfileSetupView { go(to: .experience) }
                case .experience:
                    ExperienceStep { answer in
                        model.experience = answer
                        go(to: .pick)
                    }
                case .pick:
                    PickStep(model: model) {
                        go(to: .portfolio)
                        Task { await model.buyPicked() }
                    }
                case .portfolio:
                    PortfolioStep(model: model, onKeep: onFinished)
                }
            }
            .id(step)
            .transition(
                .asymmetric(
                    insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
        .task {
            // The account's paper portfolio this flow trades in — the same one the
            // app keeps after the paywall. Signed-out people get it after the
            // sign-in step instead.
            if SessionStore.shared.isSignedIn {
                await PortfolioStore.shared.bootstrapIfNeeded()
            }
            await model.loadTokens()
        }
    }

    /// A sign-in that just created the account picks a username first.
    private var stepAfterSignIn: OnboardingStep {
        SessionStore.shared.needsProfileSetup ? .profile : .experience
    }

    private var canGoBack: Bool {
        step == .experience || step == .pick
    }

    private var header: some View {
        HStack(spacing: Space.s12) {
            Button {
                guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
                Haptics.selection()
                isMovingForward = false
                withAnimation(Motion.standard) { step = previous }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.pressable)
            .opacity(canGoBack ? 1 : 0)
            .disabled(!canGoBack)
            .accessibilityLabel("Back")

            HStack(spacing: Space.s8) {
                ForEach(OnboardingStep.allCases, id: \.self) { candidate in
                    Capsule()
                        .fill(candidate.rawValue <= step.rawValue ? Color.accent : Color.appFill)
                        .frame(height: 4)
                }
            }
            .animation(Motion.standard, value: step)
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")

            // Balances the back button so the bar stays centered.
            Color.clear.frame(width: 32, height: 32)
        }
    }

    private func go(to next: OnboardingStep) {
        Haptics.tap()
        isMovingForward = true
        withAnimation(Motion.standard) { step = next }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case balance, practice, signIn, profile, experience, pick, portfolio
}

// MARK: - Model

enum TradingExperience: String, CaseIterable {
    case never, little, lot

    var title: String {
        switch self {
        case .never: "Never"
        case .little: "A little"
        case .lot: "A lot"
        }
    }

    var detail: String {
        switch self {
        case .never: "Brand new. Keep it simple."
        case .little: "I've made a few trades."
        case .lot: "I trade most days."
        }
    }
}

enum FillState {
    case waiting
    case filling
    case filled(price: Decimal)
    case failed(String)
}

@Observable
@MainActor
final class OnboardingModel {
    static let maxPicks = 3
    /// What each picked coin gets. Fixed on purpose: no amount picker.
    static let amountPerCoin: Decimal = 1_000

    var experience: TradingExperience = .never
    private(set) var tokens: [PaperDiscoverEntry] = []
    private(set) var isLoadingTokens = true
    private(set) var tokensError: String?

    private(set) var picked: [String] = []
    private(set) var fills: [String: FillState] = [:]
    private(set) var isBuying = false
    private(set) var hasFinishedBuying = false

    /// Mark prices observed since each fill, starting at the fill price — the
    /// position charts. Every point is a real server mark.
    private(set) var samples: [String: [Double]] = [:]
    private(set) var boughtAt: [String: Date] = [:]

    /// The same coins for everyone; the answer only changes their order. New
    /// traders see the deepest, steadiest markets first, frequent traders see the
    /// biggest movers first.
    var orderedTokens: [PaperDiscoverEntry] {
        func number(_ value: Decimal?) -> Double { value.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0 }
        switch experience {
        case .never:
            return tokens.sorted { number($0.paperTradeable.liquidityUsd) > number($1.paperTradeable.liquidityUsd) }
        case .little:
            return tokens.sorted { number($0.metrics.volumeUsd) > number($1.metrics.volumeUsd) }
        case .lot:
            return tokens.sorted { abs(number($0.metrics.priceChangePct)) > abs(number($1.metrics.priceChangePct)) }
        }
    }

    func token(_ mint: String) -> PaperDiscoverEntry? {
        tokens.first { $0.mint == mint }
    }

    func loadTokens() async {
        isLoadingTokens = tokens.isEmpty
        tokensError = nil
        do {
            let response = try await DiscoverAPI.paperDiscover()
            var pool = response.entries(for: .popular).filter(\.paperTradeable.tradeable)
            if pool.count < 6 {
                let extra = response.entries(for: .mostActive).filter { entry in
                    entry.paperTradeable.tradeable && !pool.contains { $0.mint == entry.mint }
                }
                pool += extra
            }
            tokens = Array(pool.prefix(6))
        } catch {
            tokensError = error.localizedDescription
        }
        isLoadingTokens = false
    }

    func isPicked(_ mint: String) -> Bool { picked.contains(mint) }

    var canPickMore: Bool { picked.count < Self.maxPicks }

    func toggle(_ mint: String) {
        if let index = picked.firstIndex(of: mint) {
            picked.remove(at: index)
        } else if canPickMore {
            picked.append(mint)
        }
    }

    /// Buys each pick as a real paper trade, one after another, so each "Filled"
    /// lands on its own.
    func buyPicked() async {
        guard !isBuying, !hasFinishedBuying else { return }
        isBuying = true
        for mint in picked { fills[mint] = .waiting }

        if SessionStore.shared.activePortfolioId == nil {
            await PortfolioStore.shared.bootstrapIfNeeded()
        }

        for mint in picked {
            await buy(mint)
        }

        await PortfolioStore.shared.refreshAfterTrade()
        recordMarks()
        isBuying = false
        hasFinishedBuying = true
        if !boughtMints.isEmpty { Haptics.success() }
    }

    func retry(_ mint: String) async {
        guard case .failed = fills[mint] else { return }
        await buy(mint)
        await PortfolioStore.shared.refreshAfterTrade()
        recordMarks()
    }

    private func buy(_ mint: String) async {
        guard let portfolioId = SessionStore.shared.activePortfolioId else {
            fills[mint] = .failed("Couldn't open your paper portfolio.")
            return
        }
        fills[mint] = .filling
        do {
            let result = try await PaperAPI.execute(
                portfolioId: portfolioId,
                body: ExecutePaperTradeBody(
                    tokenMint: mint,
                    side: .buy,
                    notionalUsd: NSDecimalNumber(decimal: Self.amountPerCoin).stringValue
                )
            )
            fills[mint] = .filled(price: result.fill.fillPriceUsd)
            samples[mint] = [NSDecimalNumber(decimal: result.fill.fillPriceUsd).doubleValue]
            boughtAt[mint] = Date()
            Haptics.tap()
        } catch {
            fills[mint] = .failed(error.localizedDescription)
            Haptics.error()
        }
    }

    /// Mints that actually filled, in pick order.
    var boughtMints: [String] {
        picked.filter { mint in
            if case .filled = fills[mint] { return true }
            return false
        }
    }

    /// Pulls the latest snapshot and appends each held coin's current mark.
    func refreshLive() async {
        try? await PortfolioStore.shared.refresh()
        recordMarks()
    }

    private func recordMarks() {
        guard let positions = PortfolioStore.shared.snapshot?.positions else { return }
        for mint in boughtMints {
            guard let position = positions.first(where: { $0.tokenMint == mint }) else { continue }
            let mark = NSDecimalNumber(decimal: position.markPriceUsd).doubleValue
            var series = samples[mint] ?? []
            series.append(mark)
            samples[mint] = Array(series.suffix(120))
        }
    }
}

// MARK: - Step 1: balance

private struct BalanceStep: View {
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var balance: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s32) {
                BrandWordmark(height: 34)
                    .padding(.top, Space.s32)

                VStack(spacing: Space.s12) {
                    Text("Your paper balance")
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                    Text("$" + balance.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 52, weight: .semibold).monospacedDigit())
                        .tracking(-1)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    LiveBadge(text: "Live market prices")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s32)
                .padding(.horizontal, Space.s20)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))

                StepHeadline(
                    title: "Trade the real market\nwith paper money.",
                    detail: "Your trades fill at live market prices. None of it is real money, so none of it can hurt you."
                )
            }
            .padding(.horizontal, Space.margin)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button("Try a practice round", action: onContinue)
                .buttonStyle(.accent)
                .accessibilityIdentifier("onboarding.balance.continue")
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.s8)
        }
        .task {
            // Counts up through real intermediate values with an ease-out, ~1.2s.
            guard balance == 0 else { return }
            guard !reduceMotion else {
                balance = 10_000
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            let steps = 36
            for step in 1...steps {
                let progress = Double(step) / Double(steps)
                balance = (10_000 * (1 - pow(1 - progress, 3))).rounded()
                try? await Task.sleep(for: .milliseconds(33))
            }
            balance = 10_000
        }
    }
}

// MARK: - Step 2: experience

private struct ExperienceStep: View {
    var onAnswer: (TradingExperience) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s32) {
                StepHeadline(
                    title: "How much have you\ntraded before?",
                    detail: "We'll line up your coin list to match."
                )
                .padding(.top, Space.s32)

                VStack(spacing: Space.s12) {
                    ForEach(TradingExperience.allCases, id: \.self) { answer in
                        Button {
                            onAnswer(answer)
                        } label: {
                            HStack(spacing: Space.s12) {
                                VStack(alignment: .leading, spacing: Space.s4) {
                                    Text(answer.title)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text(answer.detail)
                                        .font(.rowSubtitle)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .padding(Space.s20)
                            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("onboarding.answer.\(answer.rawValue)")
                    }
                }
            }
            .padding(.horizontal, Space.margin)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Step 3: pick coins

private struct PickStep: View {
    let model: OnboardingModel
    var onBuy: () -> Void

    private var total: Decimal { OnboardingModel.amountPerCoin * Decimal(model.picked.count) }

    private var buttonTitle: String {
        switch model.picked.count {
        case 0: "Pick up to 3 coins"
        case 1: "Buy 1 coin · \(PriceFormat.usd(total))"
        default: "Buy \(model.picked.count) coins · \(PriceFormat.usd(total))"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s32) {
                StepHeadline(
                    title: "Pick your first coins",
                    detail: "Up to 3. Each one gets $1,000 of paper money at the live price."
                )
                .padding(.top, Space.s32)

                list
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s16)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button(buttonTitle.replacingOccurrences(of: ".00", with: ""), action: onBuy)
                .buttonStyle(.accent)
                .disabled(model.picked.isEmpty)
                .accessibilityIdentifier("onboarding.buy")
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.s8)
                .background(Color.appBackground)
        }
        .task {
            // Keep the list's prices current while choosing.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await model.loadTokens()
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.isLoadingTokens {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
            }
            .padding(.horizontal, Space.s16)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        } else if let error = model.tokensError, model.tokens.isEmpty {
            VStack(spacing: Space.s16) {
                EmptyStateView(symbol: "wifi.slash", title: "Couldn't load prices", detail: error)
                Button("Try again") { Task { await model.loadTokens() } }
                    .buttonStyle(.secondary)
            }
        } else {
            let tokens = model.orderedTokens
            VStack(spacing: 0) {
                ForEach(Array(tokens.enumerated()), id: \.element.id) { index, entry in
                    let isPicked = model.isPicked(entry.mint)
                    Button {
                        guard isPicked || model.canPickMore else {
                            Haptics.warning()
                            return
                        }
                        Haptics.selection()
                        withAnimation(Motion.standard) { model.toggle(entry.mint) }
                    } label: {
                        CoinPickRow(entry: entry, isPicked: isPicked, isDimmed: !isPicked && !model.canPickMore)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("onboarding.coin.\(index)")
                    .accessibilityAddTraits(isPicked ? .isSelected : [])

                    if index < tokens.count - 1 {
                        RowSeparator(leadingInset: Space.s16 + Metrics.avatar + Metrics.avatarGap)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

private struct CoinPickRow: View {
    let entry: PaperDiscoverEntry
    let isPicked: Bool
    let isDimmed: Bool

    var body: some View {
        HStack(spacing: Metrics.avatarGap) {
            TokenAvatar(mint: entry.mint, symbol: entry.symbol, logoURL: entry.logoUri.flatMap(URL.init(string:)))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.symbol ?? "?")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                Text(entry.name ?? "")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s8)
            VStack(alignment: .trailing, spacing: 2) {
                PriceText(value: entry.paperTradeable.priceUsd)
                ChangeText(percent: entry.metrics.priceChangePct)
            }
            Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isPicked ? Color.accent : Color.textTertiary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s16)
        .frame(minHeight: Metrics.rowHeight + Space.s8)
        .background(isPicked ? Color.accent.opacity(0.08) : Color.clear)
        .opacity(isDimmed ? 0.4 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Step 4: fills, then the live portfolio

private struct SellTarget: Identifiable {
    let mint: String
    let symbol: String
    let price: Decimal?
    var id: String { mint }
}

private struct PortfolioStep: View {
    let model: OnboardingModel
    var onKeep: () -> Void

    @State private var sellTarget: SellTarget?

    private var isLive: Bool { model.hasFinishedBuying && !model.boughtMints.isEmpty }

    private var positions: [PaperPosition] {
        let held = PortfolioStore.shared.snapshot?.positions ?? []
        return model.boughtMints.compactMap { mint in held.first { $0.tokenMint == mint } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s32) {
                if isLive {
                    StepHeadline(
                        title: "Your portfolio is live.",
                        detail: "These positions move with the real market, right now. Tap one to sell it."
                    )
                    .padding(.top, Space.s32)
                    summary
                    positionList
                } else {
                    StepHeadline(
                        title: model.hasFinishedBuying ? "Nothing filled yet." : "Buying your coins",
                        detail: model.hasFinishedBuying
                            ? "None of the orders went through. Retry below."
                            : "Each order fills at the live market price."
                    )
                    .padding(.top, Space.s32)
                }
                fillList
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s16)
            .animation(Motion.standard, value: isLive)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button("Keep my portfolio", action: onKeep)
                .buttonStyle(.accent)
                .disabled(!isLive)
                .accessibilityIdentifier("onboarding.keep")
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.s8)
                .background(Color.appBackground)
        }
        .task(id: model.hasFinishedBuying) {
            guard model.hasFinishedBuying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await model.refreshLive()
            }
        }
        .sheet(item: $sellTarget, onDismiss: { Task { await model.refreshLive() } }) { target in
            TradeSheetView(mint: target.mint, side: .sell, tokenSymbol: target.symbol, priceUsd: target.price)
        }
    }

    // MARK: Summary

    private var summary: some View {
        let value = positions.reduce(Decimal(0)) { $0 + $1.valueUsd }
        let cost = positions.reduce(Decimal(0)) { $0 + $1.costUsd }
        let pnl = value - cost
        let percent: Decimal? = cost > 0 ? pnl / cost * 100 : nil

        return VStack(alignment: .leading, spacing: Space.s8) {
            HStack {
                Text("Your coins")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                LiveBadge(text: "Live")
            }
            Text(PriceFormat.usd(value))
                .heroPriceStyle()
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
                .animation(Motion.standard, value: value)
            Text("\(PriceFormat.signedUSD(pnl)) (\(PriceFormat.change(percent))) since you bought")
                .font(.rowSubvalue)
                .foregroundStyle(Color.direction(percent))
                .contentTransition(.numericText())
            if let cash = PortfolioStore.shared.snapshot?.cashUsd {
                Text("\(PriceFormat.usd(cash)) paper cash left")
                    .font(.caption13Digits)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, Space.s4)
            }
        }
        .padding(Space.s20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
    }

    private var positionList: some View {
        VStack(spacing: Space.s12) {
            ForEach(positions) { position in
                Button {
                    Haptics.tap()
                    sellTarget = SellTarget(
                        mint: position.tokenMint,
                        symbol: position.token?.symbol ?? "token",
                        price: position.markPriceUsd
                    )
                } label: {
                    LivePositionCard(
                        position: position,
                        samples: model.samples[position.tokenMint] ?? [],
                        boughtAt: model.boughtAt[position.tokenMint]
                    )
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Opens a sell ticket")
            }
            ForEach(soldMints, id: \.self) { mint in
                HStack {
                    Text(model.token(mint)?.symbol ?? "Coin")
                        .font(.rowTitle)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("Sold")
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(Space.s20)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
    }

    private var soldMints: [String] {
        guard PortfolioStore.shared.snapshot != nil else { return [] }
        let held = Set(positions.map(\.tokenMint))
        return model.boughtMints.filter { !held.contains($0) }
    }

    // MARK: Fills

    /// Every order while buying; afterwards only the ones that didn't fill.
    private var visibleFills: [String] {
        model.picked.filter { mint in
            guard isLive else { return true }
            if case .filled = model.fills[mint] { return false }
            return true
        }
    }

    @ViewBuilder
    private var fillList: some View {
        let rows = visibleFills
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element) { index, mint in
                    FillRow(
                        symbol: model.token(mint)?.symbol ?? "Coin",
                        mint: mint,
                        state: model.fills[mint] ?? .waiting
                    ) {
                        Task { await model.retry(mint) }
                    }
                    if index < rows.count - 1 {
                        RowSeparator(leadingInset: Space.s16 + Metrics.avatar + Metrics.avatarGap)
                    }
                }
            }
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

private struct FillRow: View {
    let symbol: String
    let mint: String
    let state: FillState
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: Metrics.avatarGap) {
            TokenAvatar(mint: mint, symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text("Buy \(symbol)")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("$1,000 paper")
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            status
        }
        .padding(.horizontal, Space.s16)
        .frame(minHeight: Metrics.rowHeight)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .waiting:
            Text("Queued")
                .font(.rowSubtitle)
                .foregroundStyle(Color.textTertiary)
        case .filling:
            ProgressView()
        case .filled(let price):
            VStack(alignment: .trailing, spacing: 2) {
                Label("Filled", systemImage: "checkmark.circle.fill")
                    .font(.rowSubtitle.weight(.semibold))
                    .foregroundStyle(Color.accent)
                Text("at \(PriceFormat.price(price))")
                    .font(.caption13Digits)
                    .foregroundStyle(Color.textSecondary)
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .failed:
            Button("Retry", action: onRetry)
                .buttonStyle(.compact)
        }
    }
}

/// One live position: what you hold, what it's worth now, how far it's moved
/// since your fill, and a chart of its marks since then.
private struct LivePositionCard: View {
    let position: PaperPosition
    let samples: [Double]
    let boughtAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack(spacing: Metrics.avatarGap) {
                TokenAvatar(mint: position.tokenMint, symbol: position.token?.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.token?.symbol ?? "?")
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(PriceFormat.quantity(position.qty)) \(position.token?.symbol ?? "") · \(heldFor(at: context.date))")
                            .font(.caption13Digits)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PriceFormat.usd(position.valueUsd))
                        .font(.rowValue)
                        .foregroundStyle(Color.textPrimary)
                        .contentTransition(.numericText())
                    Text(position.unrealizedPnlUsd.map(PriceFormat.signedUSD) ?? "—")
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.direction(position.unrealizedPnlUsd))
                        .contentTransition(.numericText())
                }
            }

            PriceLineChart(values: chartValues, selectedIndex: .constant(nil))
                .frame(height: 56)
                .allowsHitTesting(false)
        }
        .padding(Space.s20)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .animation(Motion.standard, value: samples.count)
    }

    /// At least two points, so a fresh fill draws as a flat line from entry.
    private var chartValues: [Double] {
        if samples.count >= 2 { return samples }
        let entry = samples.first ?? NSDecimalNumber(decimal: position.avgCostUsd).doubleValue
        return [entry, entry]
    }

    private func heldFor(at now: Date) -> String {
        guard let boughtAt else { return "held" }
        let seconds = max(0, Int(now.timeIntervalSince(boughtAt)))
        if seconds < 60 { return "\(seconds)s held" }
        if seconds < 3600 { return "\(seconds / 60)m held" }
        return "\(seconds / 3600)h held"
    }
}

// MARK: - Shared pieces

private struct StepHeadline: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "● Live market prices" — a small accent dot that breathes, and the label.
struct LiveBadge: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(spacing: Space.s8) {
            Circle()
                .fill(Color.accent)
                .frame(width: 7, height: 7)
                .opacity(dim ? 0.35 : 1)
            Text(text)
                .font(.rowSubtitle)
                .foregroundStyle(Color.accent)
        }
        .onAppear {
            // Still under Reduce Motion, and under the UI screenshot walkthrough so
            // the app can go idle between steps.
            guard !reduceMotion, ProcessInfo.processInfo.environment["UITEST_STILL_FRAMES"] != "1" else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
