import SwiftUI

/// The Daily Call, at the top of the Compete tab: one featured token per UTC day,
/// call whether it closes higher or lower than its open. Calls lock at 20:00 UTC
/// and settle at 00:00 UTC on the closing price; a correct call extends your
/// streak (the flame). A paper game — simulated prices, no stakes, no prizes.
///
/// States, in order of what the card leads with:
/// - yesterday's result, once it has settled (you called it / you didn't / missed);
/// - today, open: the token, open vs live price, Higher / Lower, the countdown to lock;
/// - today, called or locked: your call, the community split, the countdown to settle.
/// The card hides itself when the server doesn't have the feature (404).
struct DailyCallCard: View {
    @State private var response: DailyCallTodayResponse?
    @State private var isLoading = true
    @State private var isUnavailable = false
    @State private var isSubmitting = false
    @State private var pendingSide: DailyCallSide?
    @State private var errorMessage: String?

    var body: some View {
        // A VStack rather than a Group, so `.task` and the refresh timer have one
        // stable view to hang on even while the card shows nothing.
        VStack(spacing: 0) {
            if isUnavailable {
                EmptyView()
            } else if let response {
                DailyCallCardContent(
                    response: response,
                    isSubmitting: isSubmitting,
                    errorMessage: errorMessage,
                    onCall: { side in pendingSide = side }
                )
            } else if isLoading {
                SkeletonBlock(height: 236, cornerRadius: Radius.card)
            }
        }
        .task { await load() }
        .autoRefresh(every: 30) { await load() }
        .confirmationDialog(
            pendingSide.map { "Call \($0.title.lowercased()) than the open?" } ?? "",
            isPresented: Binding(get: { pendingSide != nil }, set: { if !$0 { pendingSide = nil } }),
            titleVisibility: .visible,
            presenting: pendingSide
        ) { side in
            Button("Call \(side.title)") { Task { await submit(side) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Calls are final. Paper game: no stakes, no prizes.")
        }
    }

    private func load() async {
        isLoading = response == nil
        do {
            response = try await DailyCallAPI.today()
            isUnavailable = false
        } catch let error where error.isNotFound {
            isUnavailable = true
        } catch {
            // Keep whatever is on screen; the next refresh tries again.
        }
        isLoading = false
    }

    private func submit(_ side: DailyCallSide) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Haptics.commit()
        do {
            let updated = try await DailyCallAPI.call(side)
            withAnimation(Motion.standard) { response = updated }
            Haptics.success()
            // A first call can unlock "Make the Call"; the socket usually delivers it,
            // this catches it when the socket is down.
            Task {
                try? await Task.sleep(for: .seconds(2))
                await AchievementCenter.shared.checkForUnseen()
            }
        } catch {
            errorMessage = CompeteErrorText.message(for: error)
            await load()
        }
        isSubmitting = false
    }
}

/// The card's body for a loaded response. Split out so previews can render each
/// state from fixed data.
struct DailyCallCardContent: View {
    let response: DailyCallTodayResponse
    var isSubmitting: Bool = false
    var errorMessage: String? = nil
    var onCall: (DailyCallSide) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            header

            if let previous = response.previous, previous.isSettled {
                DailyCallResultBanner(call: previous)
            }

            if let call = response.call {
                today(call)
            } else {
                Text("Today's call opens shortly.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption13)
                    .foregroundStyle(Color.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(response.disclaimer ?? "Paper game: simulated prices, no stakes, no prizes.")
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dailyCall.legal")
        }
        .padding(Space.s20)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityIdentifier("dailyCall.card")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Call")
                    .font(.sectionHeader)
                    .foregroundStyle(Color.textPrimary)
                Text("Higher or lower than the open by 00:00 UTC?")
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Space.s8)
            // The streak card: flame, streak, today's token and your call.
            DailyCallShareButton(response: response, compact: true)
                .buttonStyle(.plain)
                .padding(.trailing, Space.s4)
            StreakFlame(current: response.streak.current, best: response.streak.best)
        }
    }

    // MARK: - Today

    @ViewBuilder
    private func today(_ call: DailyCall) -> some View {
        tokenRow(call)

        if let pick = call.me {
            calledRow(call, pick: pick)
        } else if call.isOpen {
            buttons
            if let lock = call.lockDate {
                HStack(spacing: 4) {
                    Image(systemName: "lock")
                    Text("Locks in")
                    CountdownText(end: lock, suffix: "", font: .caption13Digits, color: .textSecondary)
                    Text("· 20:00 UTC")
                }
                .font(.caption13)
                .foregroundStyle(Color.textSecondary)
                .accessibilityElement(children: .combine)
            }
        } else {
            Text(call.isSettled ? "Today's call has settled." : "Calls are locked for today. Results at 00:00 UTC.")
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
        }

        if let community = call.community {
            CommunitySplit(community: community)
        }
    }

    private func tokenRow(_ call: DailyCall) -> some View {
        HStack(spacing: Metrics.avatarGap) {
            TokenAvatar(mint: call.token.mint, symbol: call.token.symbol, logoURL: call.token.logoURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(call.token.displaySymbol)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("Open \(PriceFormat.price(call.openPriceUsd))")
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Space.s8)
            VStack(alignment: .trailing, spacing: 2) {
                if let live = response.livePriceUsd {
                    Text(PriceFormat.price(live))
                        .font(.rowValue)
                        .foregroundStyle(Color.textPrimary)
                        .contentTransition(.numericText())
                    Text(PriceFormat.change(changePct(open: call.openPriceUsd, now: live)) + " vs open")
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.direction(live - call.openPriceUsd))
                } else if let close = call.closePriceUsd {
                    Text(PriceFormat.price(close))
                        .font(.rowValue)
                        .foregroundStyle(Color.textPrimary)
                    Text("Close")
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text("—")
                        .font(.rowValue)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        HStack(spacing: Space.s12) {
            ForEach(DailyCallSide.allCases, id: \.self) { side in
                Button {
                    Haptics.tap()
                    onCall(side)
                } label: {
                    Label(side.title, systemImage: side.symbol)
                        .foregroundStyle(side == .higher ? Color.positive : Color.negative)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isSubmitting)
                .accessibilityIdentifier("dailyCall.\(side.rawValue)")
            }
        }
    }

    private func calledRow(_ call: DailyCall, pick: DailyCallPick) -> some View {
        HStack(spacing: Space.s8) {
            Image(systemName: pick.sideKind?.symbol ?? "questionmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(pick.sideKind == .lower ? Color.negative : Color.positive)
            Text("You called \(pick.sideKind?.title.lowercased() ?? pick.side)")
                .font(.rowTitle)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: Space.s8)
            if !call.isSettled, let end = call.endDate {
                HStack(spacing: 4) {
                    Text("Settles in")
                    CountdownText(end: end, suffix: "", font: .caption13Digits, color: .textSecondary)
                }
                .font(.caption13)
                .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dailyCall.called")
    }

    private func changePct(open: Decimal, now: Decimal) -> Decimal? {
        guard open > 0 else { return nil }
        return (now - open) / open * 100
    }
}

/// Yesterday's call, settled: which way it went and how your call did.
struct DailyCallResultBanner: View {
    let call: DailyCall

    private var headline: String {
        let symbol = call.token.displaySymbol
        switch call.result ?? "" {
        case "higher": return "\(symbol) closed higher"
        case "lower": return "\(symbol) closed lower"
        case "push": return "\(symbol) closed flat"
        default: return "Yesterday's call was voided"
        }
    }

    private var verdict: (text: String, symbol: String, color: Color) {
        guard let pick = call.me else {
            return ("You missed yesterday's call", "moon.zzz", .textSecondary)
        }
        switch pick.outcome ?? "" {
        case "correct": return ("You called it", "checkmark.circle.fill", .positive)
        case "incorrect": return ("Not this time", "xmark.circle.fill", .negative)
        case "push": return ("A push: no change to your streak", "equal.circle.fill", .textSecondary)
        default: return ("No result: no change to your streak", "minus.circle.fill", .textSecondary)
        }
    }

    var body: some View {
        HStack(spacing: Space.s12) {
            Image(systemName: verdict.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(verdict.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.text)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.caption13Digits)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s12)
        .background(Color.appSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dailyCall.result")
    }

    private var detail: String {
        guard let close = call.closePriceUsd else { return headline }
        return "\(headline): \(PriceFormat.price(call.openPriceUsd)) → \(PriceFormat.price(close)) (simulated)"
    }
}

/// The current streak as a flame, with the best beside it.
struct StreakFlame: View {
    let current: Int
    let best: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: current > 0 ? "flame.fill" : "flame")
                    .foregroundStyle(current > 0 ? AchievementTier.gold.color : Color.textTertiary)
                Text("\(current)")
                    .font(.rowValue)
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
            }
            Text("Best \(best)")
                .font(.caption13Digits)
                .foregroundStyle(Color.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak \(current), best \(best)")
        .accessibilityIdentifier("dailyCall.streak")
    }
}

/// How everyone called it: a thin split bar with both shares.
struct CommunitySplit: View {
    let community: DailyCallCommunity

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule()
                        .fill(Color.positive)
                        .frame(width: max(6, (proxy.size.width - 2) * community.higherShare))
                    Capsule()
                        .fill(Color.negative)
                }
            }
            .frame(height: 6)
            .opacity(community.sampleSize > 0 ? 1 : 0.3)
            .animation(Motion.standard, value: community.higherShare)

            HStack {
                Text("Higher \(percent(community.higherPct))")
                    .foregroundStyle(Color.positive)
                Spacer()
                Text("\(CompeteFormat.count(community.sampleSize)) calls")
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text("Lower \(percent(community.lowerPct))")
                    .foregroundStyle(Color.negative)
            }
            .font(.caption13Digits)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dailyCall.community")
    }

    private func percent(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return NSDecimalNumber(decimal: value).doubleValue.formatted(.number.precision(.fractionLength(0))) + "%"
    }
}

#if DEBUG
#Preview("Daily Call states") {
    let open = """
    { "call": { "id": "2026-10-04",
        "token": { "chain": "solana", "mint": "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm",
                   "symbol": "WIF", "name": "dogwifhat", "logoUri": null },
        "status": "open", "openPriceUsd": "1.8423", "openedAt": "2026-10-04T00:00:04Z",
        "locksAt": "2099-10-04T20:00:00Z", "endsAt": "2099-10-05T00:00:00Z",
        "closePriceUsd": null, "settledAt": null, "result": null, "community": null, "me": null },
      "livePriceUsd": "1.9011", "livePriceAt": "2026-10-04T12:00:01Z",
      "previous": { "id": "2026-10-03",
        "token": { "chain": "solana", "mint": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
                   "symbol": "BONK", "name": "Bonk", "logoUri": null },
        "status": "settled", "openPriceUsd": "0.0000213", "openedAt": "2026-10-03T00:00:04Z",
        "locksAt": "2026-10-03T20:00:00Z", "endsAt": "2026-10-04T00:00:00Z",
        "closePriceUsd": "0.0000231", "settledAt": "2026-10-04T00:00:31Z", "result": "higher",
        "community": { "higher": 62, "lower": 38, "sampleSize": 100, "higherPct": "62.0", "lowerPct": "38.0" },
        "me": { "side": "higher", "calledAt": "2026-10-03T09:12:44Z", "outcome": "correct" } },
      "streak": { "current": 3, "best": 5 },
      "disclaimer": "Paper game: simulated prices, no stakes, no prizes." }
    """
    let response = try? JSONDecoder().decode(DailyCallTodayResponse.self, from: Data(open.utf8))
    ScrollView {
        if let response {
            DailyCallCardContent(response: response)
                .padding(Space.margin)
        }
    }
    .background(Color.appBackground)
}
#endif
