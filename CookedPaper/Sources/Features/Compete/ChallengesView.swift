import SwiftUI

/// Compete → Prop Challenges. Pick a tier, get a fresh portfolio at its balance, and
/// try to reach +8% before equity touches −5%, within 30 days. The server judges it
/// every minute; this screen shows where you stand between the two lines.
///
/// Free accounts get one attempt a month; Pro is unlimited (the free tier is enforced
/// in the app, like the rest of `FreeTier`).
struct ChallengesView: View {
    static let freeAttemptsPerMonth = 1

    @State private var response: ChallengeListResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var portfolio: DuelPortfolioStore?
    @State private var isStarting = false
    @State private var confirmsAbandon = false
    @State private var showsPaywall = false
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                if isLoading && response == nil {
                    SkeletonBlock(height: 220, cornerRadius: Radius.card)
                } else if let response {
                    if let active = response.active {
                        ChallengeProgressCard(challenge: active)
                        if let portfolio {
                            ContestPortfolioSection(
                                title: "Challenge portfolio",
                                portfolio: portfolio,
                                canTrade: active.isActive,
                                emptyDetail: "Tap Trade to start. Reach \(PriceFormat.usd(active.targetEquityUsd)) to pass.",
                                onTraded: { await load() }
                            )
                        }
                        Button("Abandon challenge", role: .destructive) { confirmsAbandon = true }
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    } else {
                        tierPicker(response)
                    }
                    if !response.history.isEmpty { history(response.history) }
                    Text(response.disclaimer ?? "Paper challenge: simulated prices, no real money, no prizes.")
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    EmptyStateView(
                        symbol: "flag.checkered",
                        title: "Couldn't load challenges",
                        detail: errorMessage ?? "Check your connection and try again."
                    ) {
                        Task { await load() }
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s16)
        }
        .screenBackground()
        .reservesTabBarSpace()
        .navigationTitle("Prop Challenges")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .autoRefresh(every: 10) { await load() }
        .refreshable { await load() }
        .confirmationDialog("Abandon this challenge?", isPresented: $confirmsAbandon, titleVisibility: .visible) {
            Button("Abandon", role: .destructive) { Task { await abandon() } }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("It ends now at its current equity and counts as an attempt.")
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(reason: .locked("More challenge attempts")) { showsPaywall = false }
        }
        .alert(
            "Couldn't do that",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Sections

    private func tierPicker(_ response: ChallengeListResponse) -> some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            VStack(alignment: .leading, spacing: Space.s8) {
                Text("Pass a prop challenge")
                    .font(.appLargeTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Hit +8% before you lose 5%, within 30 days. The same rules funded traders face, practiced on paper.")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if response.attempts > 0 {
                    Text("Passed \(response.passed) of \(response.attempts) attempts")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            ForEach(response.tiers) { tier in
                Button {
                    Task { await start(tier, response: response) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(tier.tierLabel) Challenge")
                                .font(.rowTitle)
                                .foregroundStyle(Color.textPrimary)
                            Text("Pass at \(PriceFormat.usd(tier.startingBalanceUsd * (1 + tier.rules.profitTargetPct / 100))) · fail at \(PriceFormat.usd(tier.startingBalanceUsd * (1 - tier.rules.maxLossPct / 100)))")
                                .font(.rowSubtitle)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        if isStarting {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .padding(Space.s16)
                    .glassCard()
                }
                .buttonStyle(.pressable)
                .disabled(isStarting)
                .accessibilityIdentifier("challenge.start.\(tier.tier)")
            }
        }
    }

    private func history(_ items: [Challenge]) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: "Past challenges")
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: Space.s12) {
                        Image(systemName: item.status == "passed" ? "checkmark.seal.fill" : "xmark.circle")
                            .foregroundStyle(item.status == "passed" ? Color.positive : Color.textTertiary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.tierLabel) · \(item.statusTitle)")
                                .font(.rowTitle)
                                .foregroundStyle(Color.textPrimary)
                            ChangeText(percent: item.returnPct)
                        }
                        Spacer()
                        if item.status == "passed" {
                            ChallengeShareButton(challenge: item)
                        }
                    }
                    .frame(minHeight: 56)
                    if index < items.count - 1 { RowSeparator() }
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = response == nil
        do {
            let fresh = try await ChallengeAPI.list()
            response = fresh
            errorMessage = nil
            if let active = fresh.active, let id = active.portfolioId {
                if portfolio?.portfolioId != id {
                    portfolio = DuelPortfolioStore(portfolioId: id, duelId: active.id, label: "CHALLENGE")
                }
                await portfolio?.refresh()
            } else {
                portfolio = nil
            }
        } catch {
            if response == nil { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    /// Free: one attempt per calendar month. Pro: unlimited.
    private func attemptsThisMonth(_ response: ChallengeListResponse) -> Int {
        let calendar = Calendar.current
        return response.history.filter { item in
            item.startDate.map { calendar.isDate($0, equalTo: Date(), toGranularity: .month) } == true
        }.count
    }

    private func start(_ tier: ChallengeTierOffer, response: ChallengeListResponse) async {
        guard !isStarting else { return }
        if !FreeTier.shared.isPro, attemptsThisMonth(response) >= Self.freeAttemptsPerMonth {
            showsPaywall = true
            return
        }
        isStarting = true
        Haptics.commit()
        do {
            _ = try await ChallengeAPI.start(tier: tier.tier)
            Haptics.success()
            await load()
        } catch {
            actionError = CompeteErrorText.message(for: error)
        }
        isStarting = false
    }

    private func abandon() async {
        guard let active = response?.active else { return }
        do {
            _ = try await ChallengeAPI.abandon(id: active.id)
            await load()
        } catch {
            actionError = CompeteErrorText.message(for: error)
        }
    }
}

/// The running challenge: equity, return, and a bar from the fail line to the pass line.
struct ChallengeProgressCard: View {
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack {
                Text("\(challenge.tierLabel) Challenge")
                    .font(.sectionHeader)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let end = challenge.endDate {
                    CountdownText(end: end)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(challenge.equityUsd.map { PriceFormat.usd($0) } ?? "—")
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                ChangeText(percent: challenge.returnPct, font: .rowValue)
            }
            VStack(spacing: Space.s8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.appSeparator)
                        Capsule()
                            .fill((challenge.progress ?? 0) >= 0.5 ? Color.positive : Color.negative)
                            .frame(width: geo.size.width * (challenge.progress ?? 0))
                    }
                }
                .frame(height: 10)
                .accessibilityElement()
                .accessibilityLabel("Progress from the fail line to the pass line")
                .accessibilityValue("\(Int(((challenge.progress ?? 0) * 100).rounded())) percent")
                HStack {
                    Text("Fail \(PriceFormat.usd(challenge.floorEquityUsd))")
                    Spacer()
                    Text("Start \(PriceFormat.usd(challenge.startingBalanceUsd))")
                    Spacer()
                    Text("Pass \(PriceFormat.usd(challenge.targetEquityUsd))")
                }
                .font(.caption13Digits)
                .foregroundStyle(Color.textSecondary)
            }
            Text("Judged every minute on your portfolio's live value.")
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(Space.s20)
        .glassCard()
    }
}

/// "Passed the $50K Challenge", as a share card.
struct ChallengeShareButton: View {
    let challenge: Challenge

    var body: some View {
        ShareImageButton(
            id: challenge.id,
            title: "I passed the \(challenge.tierLabel) Challenge",
            message: "Passed the \(challenge.tierLabel) prop challenge on Cooked. Paper trading. cooked.trade",
            compact: true,
            label: "Share"
        ) { _ in
            ChallengeShareCard(challenge: challenge)
        }
    }
}

struct ChallengeShareCard: View {
    let challenge: Challenge

    var body: some View {
        ZStack {
            ShareCardStyle.background
            RadialGradient(colors: [ShareCardStyle.glow.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 320)
            VStack(alignment: .leading, spacing: 16) {
                Text("PROP CHALLENGE")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.6))
                Text("PASSED")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(Color.positive)
                Text("the \(challenge.tierLabel) Challenge")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Text(ShareCardFormat.pnl(challenge.returnPct))
                    .font(.system(size: 40, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.positive)
                Text("+8% target · 5% max loss · 30 days")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer(minLength: 0)
                HStack {
                    BrandWordmark(height: 20)
                    Spacer()
                    Text(ShareCardStyle.footer)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .padding(28)
        }
    }
}
