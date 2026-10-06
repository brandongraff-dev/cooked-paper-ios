import SwiftUI

/// A contest's own portfolio (a challenge, a room), traded with the duel screens'
/// machinery: the coin picker, then the regular buy, sell and leverage tickets pointed
/// at this portfolio, never the main one.
///
/// Shows the holdings, a Trade button while `canTrade`, and owns the sheets. The
/// caller supplies the store and refreshes it; `onTraded` runs after a ticket closes.
struct ContestPortfolioSection: View {
    let title: String
    let portfolio: DuelPortfolioStore
    let canTrade: Bool
    /// Shown with no positions while trading is open.
    var emptyDetail = "Tap Trade to buy your first coin."
    var onTraded: () async -> Void = {}

    @State private var showsPicker = false
    @State private var pendingIntent: DuelTradeIntent?
    @State private var tradeIntent: DuelTradeIntent?
    @State private var leveragedSelection: DuelLeveragedSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(
                title: title,
                caption: portfolio.snapshot.map { "\(PriceFormat.usd($0.cashUsd)) cash" }
            )
            holdings
            if canTrade {
                Button {
                    Haptics.tap()
                    showsPicker = true
                } label: {
                    Label("Trade", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(.accent)
                .accessibilityIdentifier("contest.trade")
            }
        }
        .sheet(isPresented: $showsPicker, onDismiss: {
            // The picker hands back a choice and closes; open its ticket once it's gone.
            if let next = pendingIntent {
                pendingIntent = nil
                tradeIntent = next
            }
        }) {
            DuelCoinPicker(portfolio: portfolio) { intent in
                pendingIntent = intent
            }
        }
        .sheet(item: $tradeIntent, onDismiss: { Task { await onTraded() } }) { intent in
            switch intent.kind {
            case .buy:
                TradeSheetView(mint: intent.mint, side: .buy, tokenSymbol: intent.symbol, priceUsd: intent.priceUsd, portfolio: .duel(intent.portfolio))
            case .sell:
                TradeSheetView(mint: intent.mint, side: .sell, tokenSymbol: intent.symbol, priceUsd: intent.priceUsd, portfolio: .duel(intent.portfolio))
            case .leverage:
                LeverageSheetView(mint: intent.mint, tokenSymbol: intent.symbol, portfolio: .duel(intent.portfolio))
            }
        }
        .sheet(item: $leveragedSelection, onDismiss: { Task { await onTraded() } }) { selection in
            LeveragedPositionSheet(positionId: selection.id, portfolio: .duel(selection.portfolio))
        }
    }

    @ViewBuilder
    private var holdings: some View {
        if let snapshot = portfolio.snapshot {
            let spot = snapshot.positions
            let leveraged = snapshot.leveragedPositions ?? []
            if spot.isEmpty && leveraged.isEmpty {
                EmptyStateView(
                    symbol: "chart.pie",
                    title: canTrade ? "No positions yet" : "No open positions",
                    detail: canTrade ? emptyDetail : "This portfolio is closed."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(spot.enumerated()), id: \.element.id) { index, position in
                        Button {
                            guard canTrade else { return }
                            Haptics.tap()
                            tradeIntent = DuelTradeIntent(
                                mint: position.tokenMint,
                                symbol: position.token?.symbol ?? "token",
                                priceUsd: position.markPriceUsd,
                                kind: .sell,
                                portfolio: portfolio
                            )
                        } label: {
                            DuelPositionRow(position: position)
                        }
                        .buttonStyle(.pressable)
                        if index < spot.count - 1 || !leveraged.isEmpty { RowSeparator() }
                    }
                    ForEach(Array(leveraged.enumerated()), id: \.element.id) { index, position in
                        Button {
                            Haptics.tap()
                            leveragedSelection = DuelLeveragedSelection(id: position.id, portfolio: portfolio)
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
        } else if let message = portfolio.errorMessage {
            Text(message)
                .font(.caption13)
                .foregroundStyle(Color.textSecondary)
        } else {
            SkeletonBlock(height: 120, cornerRadius: Radius.card)
        }
    }
}
