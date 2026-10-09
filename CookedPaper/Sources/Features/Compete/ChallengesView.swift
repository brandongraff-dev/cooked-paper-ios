import SwiftUI

/// Compete → Prop Challenges. A ladder: Rookie $10K (+8% / −5%), then Pro $50K
/// (+10% / −5%) once Rookie is passed, then Elite $100K (+12% / −4%). Each start is a
/// fresh portfolio at the tier's balance, with 30 days to hit the target before equity
/// touches the floor. The server judges it
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
    /// The tier tapped, waiting on the start sheet.
    @State private var pendingTier: ChallengeTierOffer?

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
                    if !response.history.isEmpty {
                        history(response.history)
                    } else if response.active == nil, let first = response.tiers.first(where: \.isUnlocked) {
                        EmptyStateView(
                            symbol: "flag.checkered",
                            title: "No challenges yet",
                            action: EmptyStateAction(
                                title: "Start the \(first.tierLabel) Challenge",
                                identifier: "challenge.firstStart"
                            ) {
                                choose(first, response: response)
                            },
                            compact: true
                        )
                    }
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
        .sheet(item: $pendingTier) { tier in
            ChallengeStartSheet(tier: tier, attemptsNote: response.flatMap { attemptsNote($0) }, isStarting: isStarting) {
                guard let response else { return }
                Task {
                    let error = await start(tier, response: response)
                    pendingTier = nil
                    // Show a failure once the sheet is gone, so the alert isn't lost behind it.
                    if let error {
                        try? await Task.sleep(for: .milliseconds(450))
                        actionError = error
                    }
                }
            }
            .presentationDetents([.height(520), .large])
            .presentationDragIndicator(.visible)
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
            VStack(alignment: .leading, spacing: Space.s12) {
                InfoPillRow(pills: [
                    (symbol: "arrow.up.forward", text: "Pass one to unlock the next"),
                    (symbol: "clock.fill", text: "\(response.tiers.first?.rules.days ?? 30) days"),
                ])
                if let note = attemptsNote(response) {
                    Label(note, systemImage: FreeTier.shared.isPro ? "infinity" : "ticket.fill")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            ForEach(response.tiers) { tier in
                Button {
                    Haptics.tap()
                    choose(tier, response: response)
                } label: {
                    ChallengeTierCard(tier: tier, isStarting: isStarting)
                }
                .buttonStyle(.pressable)
                .disabled(isStarting || !tier.isUnlocked)
                .accessibilityLabel("\(tier.tierLabel) challenge")
                .accessibilityHint(tier.isUnlocked ? "" : "Locked. Pass the \(tier.requiresLabel ?? "previous") challenge first.")
                .accessibilityIdentifier("challenge.start.\(tier.tier)")
            }
        }
    }

    private func history(_ items: [Challenge]) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: "Past challenges", caption: passedCaption(items))
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: Space.s12) {
                        TierEmblem(level: ChallengeRank.level(item.tier), size: 34, lit: item.status == "passed")
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

    /// A tier tapped: the start sheet, or the paywall once the free attempt is used.
    private func choose(_ tier: ChallengeTierOffer, response: ChallengeListResponse) {
        if needsPaywall(response) {
            showsPaywall = true
        } else {
            pendingTier = tier
        }
    }

    private func passedCaption(_ items: [Challenge]) -> String {
        let passed = items.filter { $0.status == "passed" }.count
        return "\(passed) of \(items.count) passed"
    }

    /// Free: how many of this month's attempts are left. Pro: unlimited.
    private func attemptsNote(_ response: ChallengeListResponse) -> String? {
        if FreeTier.shared.isPro { return "Unlimited attempts with Pro" }
        let left = max(0, Self.freeAttemptsPerMonth - attemptsThisMonth(response))
        return left > 0
            ? "\(left) free \(left == 1 ? "attempt" : "attempts") left this month"
            : "Free attempt used this month. Pro gets unlimited."
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

    private func needsPaywall(_ response: ChallengeListResponse) -> Bool {
        !FreeTier.shared.isPro && attemptsThisMonth(response) >= Self.freeAttemptsPerMonth
    }

    /// Starts `tier`; returns the error to show, if any.
    private func start(_ tier: ChallengeTierOffer, response: ChallengeListResponse) async -> String? {
        guard !isStarting else { return nil }
        isStarting = true
        defer { isStarting = false }
        Haptics.commit()
        do {
            _ = try await ChallengeAPI.start(tier: tier.tier)
            Haptics.success()
            await load()
            return nil
        } catch {
            return CompeteErrorText.message(for: error)
        }
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

/// The running challenge: its rank badge, equity, return, and the rail from the fail
/// line to the pass line.
struct ChallengeProgressCard: View {
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack(spacing: Space.s12) {
                TierEmblem(level: ChallengeRank.level(challenge.tier), size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(ChallengeRank.name(challenge.tier).uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.textSecondary)
                    Text("\(challenge.tierLabel) Challenge")
                        .font(.sectionHeader)
                        .foregroundStyle(Color.textPrimary)
                }
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
                ChallengeRail(marker: challenge.progress ?? 0, fill: true)
                .accessibilityElement()
                .accessibilityLabel("Progress from the fail line to the pass line")
                .accessibilityValue("\(Int(((challenge.progress ?? 0) * 100).rounded())) percent")
                HStack {
                    Text("Out \(PriceFormat.compact(challenge.floorEquityUsd))")
                    Spacer()
                    Text("Pass \(PriceFormat.compact(challenge.targetEquityUsd))")
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
                Text("+\(ChallengeTierCard.percent(challenge.rules.profitTargetPct)) target · \(ChallengeTierCard.percent(challenge.rules.maxLossPct)) max loss · \(challenge.rules.days) days")
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

/// A tier to start: its rank badge and name, the balance, and the rail from the fail
/// line to the pass line with a marker where you'd begin.
private struct ChallengeTierCard: View {
    let tier: ChallengeTierOffer
    let isStarting: Bool

    var body: some View {
        let start = tier.startingBalanceUsd
        let pass = start * (1 + tier.rules.profitTargetPct / 100)
        let fail = start * (1 - tier.rules.maxLossPct / 100)
        let ratio = NSDecimalNumber(decimal: (start - fail) / max(pass - fail, 1)).doubleValue
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack(spacing: Space.s16) {
                TierEmblem(level: ChallengeRank.level(tier.tier), size: 52, lit: tier.isUnlocked)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ChallengeRank.name(tier.tier).uppercased()) · +\(Self.percent(tier.rules.profitTargetPct)) / \u{2212}\(Self.percent(tier.rules.maxLossPct))")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.textSecondary)
                    Text(tier.tierLabel)
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundStyle(tier.isUnlocked ? Color.textPrimary : Color.textTertiary)
                }
                Spacer()
                if isStarting {
                    ProgressView()
                } else {
                    Image(systemName: tier.isUnlocked ? "chevron.right" : "lock.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            if tier.isUnlocked {
                VStack(spacing: Space.s8) {
                    ChallengeRail(marker: ratio)
                    HStack {
                        Text("Out \(PriceFormat.compact(fail))")
                        Spacer()
                        Text("Pass \(PriceFormat.compact(pass))")
                    }
                    .font(.caption13Digits)
                    .foregroundStyle(Color.textSecondary)
                }
            } else {
                Label("Pass the \(tier.requiresLabel ?? "previous") challenge to unlock", systemImage: "lock.fill")
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(Space.s20)
        .glassCard()
    }

    static func percent(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).doubleValue.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }
}

/// What you're about to start: the rank badge, the balance, the three rules in
/// dollars, and one button. Starting can't be undone without it counting as an attempt.
private struct ChallengeStartSheet: View {
    let tier: ChallengeTierOffer
    let attemptsNote: String?
    let isStarting: Bool
    let onStart: () -> Void

    var body: some View {
        let start = tier.startingBalanceUsd
        let target = start * tier.rules.profitTargetPct / 100
        let loss = start * tier.rules.maxLossPct / 100
        VStack(alignment: .leading, spacing: Space.s20) {
            // The same header as the tier's card, so the sheet reads as that card opened.
            HStack(spacing: Space.s16) {
                TierEmblem(level: ChallengeRank.level(tier.tier), size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ChallengeRank.name(tier.tier).uppercased()) CHALLENGE")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.textSecondary)
                    Text(whole(start))
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text("Starting balance")
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.top, Space.s32)

            VStack(spacing: 0) {
                rule("flag.fill", "Profit target", "+\(whole(target))", detail: "Pass at \(PriceFormat.compact(start + target))")
                RowSeparator(leadingInset: 44)
                rule("shield.fill", "Max loss", "\u{2212}\(whole(loss))", detail: "Out at \(PriceFormat.compact(start - loss))")
                RowSeparator(leadingInset: 44)
                rule("clock.fill", "Time limit", "\(tier.rules.days) days", detail: nil)
            }
            .padding(.horizontal, Space.s16)
            .glassCard()

            Spacer(minLength: 0)

            VStack(spacing: Space.s12) {
                Button(action: onStart) {
                    if isStarting {
                        ProgressView().tint(Color.accentInk)
                    } else {
                        Text("Start \(tier.tierLabel) Challenge")
                    }
                }
                .buttonStyle(.accent)
                .disabled(isStarting)
                .accessibilityIdentifier("challenge.confirm")
                if let attemptsNote {
                    Text(attemptsNote)
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.s16)
        .frame(maxWidth: .infinity)
        .screenBackground()
        .preferredColorScheme(.dark)
    }

    /// $50,000, no cents: these are round rule amounts.
    private func whole(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private func rule(_ symbol: String, _ title: String, _ value: String, detail: String?) -> some View {
        HStack(spacing: Space.s12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accent)
                .frame(width: 32, height: 32)
                .metalSurface(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.caption13Digits)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer()
            Text(value)
                .font(.rowValue.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}
