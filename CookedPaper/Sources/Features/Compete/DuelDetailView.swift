import SwiftUI

/// One duel: both players head to head (live return, equity, who's leading), the
/// clock, your duel portfolio, and Trade — which opens the regular buy, sell and
/// leverage tickets pointed at this duel's portfolio, never the main one.
/// Refreshes every ~5 seconds while on screen, and at once on a `paper:duel`
/// socket event for this duel.
struct DuelDetailView: View {
    let duelId: String

    @State private var duel: Duel?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var duelPortfolio: DuelPortfolioStore?
    @State private var showsPicker = false
    @State private var pendingIntent: DuelTradeIntent?
    @State private var tradeIntent: DuelTradeIntent?
    @State private var leveragedSelection: DuelLeveragedSelection?
    @State private var isActing = false
    @State private var actionError: String?
    private let store = DuelsStore.shared

    init(duelId: String, initial: Duel? = nil) {
        self.duelId = duelId
        _duel = State(initialValue: initial)
        _isLoading = State(initialValue: initial == nil)
    }

    var body: some View {
        Group {
            if let duel {
                content(duel)
            } else if isLoading {
                skeleton
            } else {
                EmptyStateView(
                    symbol: "figure.fencing",
                    title: "Couldn't open this duel",
                    detail: errorMessage ?? "It may have been cancelled."
                ) {
                    Task { await refresh() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
        .reservesTabBarSpace()
        .navigationTitle(duel.map { "vs \($0.them?.handle ?? "open invite")" } ?? "Duel")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .autoRefresh(every: 5) { await refresh() }
        .onChange(of: store.eventVersion) { _, _ in
            guard let event = store.lastEvent, event.id == duelId else { return }
            withAnimation(Motion.standard) { duel = event }
            syncPortfolio(event)
        }
        .sheet(isPresented: $showsPicker, onDismiss: {
            // The picker hands back a choice and closes; open its ticket once it's gone.
            if let next = pendingIntent {
                pendingIntent = nil
                tradeIntent = next
            }
        }) {
            if let duelPortfolio {
                DuelCoinPicker(portfolio: duelPortfolio) { intent in
                    pendingIntent = intent
                }
            }
        }
        .sheet(item: $tradeIntent, onDismiss: { Task { await refresh() } }) { intent in
            switch intent.kind {
            case .buy:
                TradeSheetView(mint: intent.mint, side: .buy, tokenSymbol: intent.symbol, priceUsd: intent.priceUsd, portfolio: .duel(intent.portfolio))
            case .sell:
                TradeSheetView(mint: intent.mint, side: .sell, tokenSymbol: intent.symbol, priceUsd: intent.priceUsd, portfolio: .duel(intent.portfolio))
            case .leverage:
                LeverageSheetView(mint: intent.mint, tokenSymbol: intent.symbol, portfolio: .duel(intent.portfolio))
            }
        }
        .sheet(item: $leveragedSelection, onDismiss: { Task { await refresh() } }) { selection in
            LeveragedPositionSheet(positionId: selection.id, portfolio: .duel(selection.portfolio))
        }
        .alert(
            "Couldn't update the duel",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Content

    private func content(_ duel: Duel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(spacing: Space.s16) {
                    statusLine(duel)
                    HeadToHeadCard(duel: duel)
                }
                actions(duel)
                if duel.state == .active || duel.state == .finished {
                    positions(duel)
                }
                CompeteLegalCaption()
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.section)
        }
        .scrollIndicators(.hidden)
        .refreshable { await refresh() }
    }

    @ViewBuilder
    private func statusLine(_ duel: Duel) -> some View {
        HStack(spacing: Space.s8) {
            switch duel.state {
            case .active:
                Circle()
                    .fill(Color.positive)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text("Live · \(duel.durationLabel) duel")
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if let end = duel.endDate {
                    CountdownText(end: end, font: .rowValue, color: .textPrimary)
                        .accessibilityIdentifier("duel.countdown")
                }
            case .pending:
                Image(systemName: "hourglass")
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                Text(duel.isChallenger
                     ? (duel.opponent == nil ? "Waiting for someone to join" : "Waiting for \(duel.opponent?.handle ?? "them") to accept")
                     : "\(duel.challenger.handle) challenged you")
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(duel.durationLabel)
                    .font(.caption13Digits)
                    .foregroundStyle(Color.textTertiary)
            case .finished:
                Text(duel.outcome?.title ?? "Finished")
                    .font(.rowTitle)
                    .foregroundStyle(outcomeColor(duel.outcome))
                Spacer()
                Text(finishedLine(duel))
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
            case .declined, .cancelled, .expired, .unknown:
                Text(endedLine(duel.state))
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func actions(_ duel: Duel) -> some View {
        switch duel.state {
        case .active:
            if duelPortfolio != nil {
                Button {
                    Haptics.tap()
                    showsPicker = true
                } label: {
                    Label("Trade", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("duel.trade")
            }
        case .pending:
            if duel.isChallenger {
                VStack(spacing: Space.s12) {
                    if let url = duel.inviteURL {
                        ShareLink(
                            item: url,
                            subject: Text("Duel me on Cooked"),
                            message: Text("Duel me on Cooked: $1,000 in paper money each, best return wins. No stakes, just bragging rights.")
                        ) {
                            Label("Share invite link", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.primary)
                    }
                    Button("Cancel invite") { act { [id = duel.id] in try await DuelsAPI.cancel(id: id) } }
                        .buttonStyle(.secondary)
                        .disabled(isActing)
                        .accessibilityIdentifier("duel.cancel")
                }
            } else {
                HStack(spacing: Space.s12) {
                    Button("Decline") { act { [id = duel.id] in try await DuelsAPI.decline(id: id) } }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("duel.decline")
                    Button {
                        Haptics.commit()
                        act { [id = duel.id] in try await DuelsAPI.accept(id: id) }
                    } label: {
                        if isActing {
                            ProgressView().tint(Color.inverseText)
                        } else {
                            Text("Accept")
                        }
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("duel.accept")
                }
                .disabled(isActing)
            }
        case .finished:
            VStack(spacing: Space.s12) {
                if duel.them != nil {
                    Button {
                        Haptics.tap()
                        act { [id = duel.id] in try await DuelsAPI.rematch(id: id) }
                    } label: {
                        if isActing {
                            ProgressView().tint(Color.inverseText)
                        } else {
                            Label("Rematch", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(isActing)
                    .accessibilityIdentifier("duel.rematch")
                }
                // The result as an image: you vs them, both returns, WIN/LOSS.
                DuelShareButton(duel: duel)
                    .buttonStyle(.secondary)
            }
        case .declined, .cancelled, .expired, .unknown:
            EmptyView()
        }
    }

    @ViewBuilder
    private func positions(_ duel: Duel) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(
                title: "Your duel portfolio",
                caption: duelPortfolio?.snapshot.map { "\(PriceFormat.usd($0.cashUsd)) cash" }
            )
            if let snapshot = duelPortfolio?.snapshot {
                let spot = snapshot.positions
                let leveraged = snapshot.leveragedPositions ?? []
                if spot.isEmpty && leveraged.isEmpty {
                    EmptyStateView(
                        symbol: "chart.pie",
                        title: duel.state == .active ? "No positions yet" : "No open positions",
                        detail: duel.state == .active
                            ? "Tap Trade to buy your first coin with your $1,000."
                            : "This duel's portfolio is closed."
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(spot.enumerated()), id: \.element.id) { index, position in
                            Button {
                                guard duel.state == .active, let portfolioStore = duelPortfolio else { return }
                                Haptics.tap()
                                tradeIntent = DuelTradeIntent(
                                    mint: position.tokenMint,
                                    symbol: position.token?.symbol ?? "token",
                                    priceUsd: position.markPriceUsd,
                                    kind: .sell,
                                    portfolio: portfolioStore
                                )
                            } label: {
                                DuelPositionRow(position: position)
                            }
                            .buttonStyle(.pressable)
                            .accessibilityIdentifier("duel.position.\(index)")
                            if index < spot.count - 1 || !leveraged.isEmpty { RowSeparator() }
                        }
                        ForEach(Array(leveraged.enumerated()), id: \.element.id) { index, position in
                            Button {
                                guard let portfolioStore = duelPortfolio else { return }
                                Haptics.tap()
                                leveragedSelection = DuelLeveragedSelection(id: position.id, portfolio: portfolioStore)
                            } label: {
                                ListRow(title: position.symbol, subtitle: position.label) {
                                    TokenAvatar(mint: position.tokenMint, symbol: position.token?.symbol)
                                } trailing: {
                                    Text(PriceFormat.usd(position.valueUsd))
                                        .font(.rowValue)
                                        .foregroundStyle(Color.textPrimary)
                                    ChangeText(percent: position.unrealizedReturnOnMarginPct)
                                }
                            }
                            .buttonStyle(.pressable)
                            if index < leveraged.count - 1 { RowSeparator() }
                        }
                    }
                }
            } else if let message = duelPortfolio?.errorMessage {
                Text(message)
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { _ in SkeletonRow() }
                }
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s16) {
            SkeletonBlock(height: 16)
            SkeletonBlock(height: 220, cornerRadius: Radius.card)
            SkeletonBlock(height: Metrics.buttonHeight, cornerRadius: Metrics.buttonHeight / 2)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s8)
    }

    // MARK: - Copy

    private func outcomeColor(_ outcome: DuelOutcome?) -> Color {
        switch outcome {
        case .won: .positive
        case .lost: .negative
        case .draw, nil: .textPrimary
        }
    }

    private func finishedLine(_ duel: Duel) -> String {
        guard let raw = duel.finishedAt ?? duel.endsAt, let date = CompeteDate.parse(raw) else { return "Results are simulated" }
        return "Ended \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }

    private func endedLine(_ state: DuelStatus) -> String {
        switch state {
        case .declined: "This invite was declined."
        case .cancelled: "This invite was cancelled."
        case .expired: "This invite expired."
        default: "This duel is no longer active."
        }
    }

    // MARK: - Networking

    private func refresh() async {
        do {
            let fresh = try await DuelsAPI.duel(id: duelId)
            if fresh != duel {
                withAnimation(Motion.standard) { duel = fresh }
            }
            errorMessage = nil
            syncPortfolio(fresh)
        } catch {
            if duel == nil { errorMessage = CompeteErrorText.message(for: error) }
        }
        isLoading = false
        await duelPortfolio?.refresh()
    }

    /// Creates the portfolio store once the duel has a portfolio for you.
    private func syncPortfolio(_ duel: Duel) {
        guard let portfolioId = duel.me?.portfolioId, !portfolioId.isEmpty else { return }
        if duelPortfolio?.portfolioId != portfolioId {
            let fresh = DuelPortfolioStore(portfolioId: portfolioId, duelId: duel.id)
            duelPortfolio = fresh
            Task { await fresh.refresh() }
        }
    }

    private func act(_ action: @escaping @MainActor () async throws -> Duel) {
        guard !isActing else { return }
        isActing = true
        Task {
            do {
                let updated = try await action()
                Haptics.success()
                store.didChange(updated)
                if updated.id == duelId {
                    withAnimation(Motion.standard) { duel = updated }
                    syncPortfolio(updated)
                }
            } catch {
                Haptics.error()
                actionError = CompeteErrorText.message(for: error)
            }
            isActing = false
        }
    }
}

struct DuelLeveragedSelection: Identifiable {
    let id: String
    let portfolio: DuelPortfolioStore
}

// MARK: - Head to head

/// You on the left, them on the right: avatar, name, live return (big), equity,
/// and a crown on whoever leads, over the split bar.
private struct HeadToHeadCard: View {
    let duel: Duel

    var body: some View {
        VStack(spacing: Space.s20) {
            HStack(alignment: .top, spacing: Space.s12) {
                side(player: duel.me, label: "You", isLeading: duel.leader == .me, alignment: .leading)
                Text("vs")
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 28)
                side(player: duel.them, label: duel.them?.handle ?? "Open invite", isLeading: duel.leader == .them, alignment: .trailing)
            }
            HeadToHeadBar(mine: duel.me?.returnPct, theirs: duel.them?.returnPct, height: 8)
            HStack {
                Text(leadLine)
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                SimulatedCaption()
            }
        }
        .padding(Space.s20)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("duel.headToHead")
    }

    private var leadLine: String {
        switch duel.leader {
        case .me: duel.state == .finished ? "You finished ahead" : "You're leading"
        case .them: duel.state == .finished ? "They finished ahead" : "They're leading"
        case .tied: "Dead even"
        case nil: duel.state == .pending ? "Starts when accepted" : "Waiting for prices"
        }
    }

    private func side(player: DuelPlayer?, label: String, isLeading: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Space.s8) {
            OpponentAvatar(player: player, size: 56)
                .overlay(alignment: .topTrailing) {
                    if isLeading {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AchievementTier.gold.color)
                            .padding(5)
                            .background(Color.appSurface, in: Circle())
                            .offset(x: 6, y: -6)
                            .transition(AnyTransition.scale.combined(with: .opacity))
                    }
                }
            Text(label)
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            ChangeText(percent: player?.returnPct, font: .title.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(player?.equityUsd.map(PriceFormat.usd) ?? "—")
                .font(.rowSubvalue)
                .foregroundStyle(Color.textSecondary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .animation(Motion.standard, value: isLeading)
    }
}

struct DuelPositionRow: View {
    let position: PaperPosition

    var body: some View {
        ListRow(
            title: position.token?.symbol ?? "?",
            subtitle: "\(PriceFormat.quantity(position.qty)) tokens"
        ) {
            TokenAvatar(mint: position.tokenMint, symbol: position.token?.symbol)
        } trailing: {
            Text(PriceFormat.usd(position.valueUsd))
                .font(.rowValue)
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
            ChangeText(percent: position.unrealizedReturnPct)
        }
    }
}
