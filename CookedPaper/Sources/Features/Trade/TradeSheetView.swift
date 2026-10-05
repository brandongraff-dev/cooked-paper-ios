import Foundation
import StoreKit
import SwiftUI

/// The buy/sell ticket. Buy takes a dollar amount (quick-filled from a % of cash,
/// but always sent as `notionalUsd` — the server resolves it against the live price
/// at fill time regardless of how the client arrived at the number). Sell uses the
/// server's own `sellPercent` (25/50/75/100) primitive directly rather than
/// client-computing a quantity — the backend's own rule is "never a client-side
/// multiply against a render that may be stale," and `sellPercent` is exactly the
/// escape hatch it ships for that.
struct TradeSheetView: View {
    let mint: String
    let side: TradeSide
    let tokenSymbol: String
    /// Last known price, only for the "≈ N TOKEN" preview under the amount before a
    /// quote arrives. The order itself is always priced server-side.
    var priceUsd: Decimal? = nil
    /// The portfolio this ticket trades in: the account's main one unless a duel
    /// passes its own (see `TradePortfolioContext`).
    var portfolio: TradePortfolioContext = .main

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @State private var amountText = ""
    @State private var sellPercent: Int?
    @State private var quote: PaperQuoteResponse?
    @State private var isQuoting = false
    @State private var isExecuting = false
    @State private var errorMessage: String?
    @State private var fillResult: ExecutePaperTradeResponse?
    /// The position's average cost just before a sell, for the trade card's entry.
    @State private var soldAverageCost: Decimal?
    @State private var quoteTask: Task<Void, Never>?
    @State private var showsPaywall = false
    @State private var paywallReason: PaywallReason = .outOfTrades
    /// A profitable sell on the free tier: the fill confirmation offers Pro.
    @State private var offersProAfterWin = false

    /// The free tier's daily buy limit applies to the main portfolio only; duels
    /// and selling are never limited.
    private var isOutOfFreeTrades: Bool {
        side == .buy && portfolio.isMain && !FreeTier.shared.canTrade
    }

    private var cashUsd: Decimal { portfolio.snapshot?.cashUsd ?? 0 }
    private var position: PaperPosition? {
        portfolio.snapshot?.positions.first { $0.tokenMint == mint }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let fillResult {
                    FillConfirmationView(
                        result: fillResult,
                        symbol: tokenSymbol,
                        // A sell with a known entry gets the on-device image card.
                        shareCard: shareCard(for: fillResult),
                        // A sell has a result worth sharing: this token's card
                        // (main portfolio only; a duel's result is the duel itself).
                        shareSubjectPath: fillResult.trade.side == .sell && portfolio.isMain
                            ? portfolio.portfolioId.map { ShareCardSubject.position(portfolioId: $0, mint: mint) }
                            : nil,
                        onSeePro: offersProAfterWin ? showAfterWinPaywall : nil
                    ) { dismiss() }
                } else if isOutOfFreeTrades {
                    OutOfFreeTradesView {
                        paywallReason = .outOfTrades
                        showsPaywall = true
                    }
                } else {
                    form
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appSurfaceElevated)
            .navigationTitle("\(side == .buy ? "Buy" : "Sell") \(tokenSymbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(reason: paywallReason) { showsPaywall = false }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.s16)

            amountDisplay

            Spacer(minLength: Space.s16)

            VStack(spacing: Space.s16) {
                availableLine
                if side == .buy, portfolio.isMain, FreeTier.shared.isLimited {
                    Text("\(FreeTier.shared.tradesLeftToday) of \(FreeTier.freeTradesPerDay) free buys left today")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("trade.freeTradesLeft")
                }
                quickAmountRow
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                        .multilineTextAlignment(.center)
                }
                if side == .buy {
                    NumericKeypad(text: $amountText)
                        .onChange(of: amountText) { _, _ in requestQuote() }
                }
                Button {
                    Task { await execute() }
                } label: {
                    if isExecuting {
                        ProgressView().tint(Color.inverseText)
                    } else {
                        Text("Review")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!canSubmit || isExecuting)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s8)
        }
    }

    // MARK: - Amount

    private var amountDisplay: some View {
        VStack(spacing: Space.s8) {
            if side == .buy {
                Text(amountText.isEmpty ? "$0" : "$" + groupedAmount)
                    .font(.amountEntry)
                    .tracking(-1)
                    .foregroundStyle(amountText.isEmpty ? Color.textTertiary : Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(Motion.press, value: amountText)
            } else {
                Text(sellPercent.map { "\($0)%" } ?? "0%")
                    .font(.amountEntry)
                    .tracking(-1)
                    .foregroundStyle(sellPercent == nil ? Color.textTertiary : Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Motion.press, value: sellPercent)
            }

            Text(estimateLine)
                .font(.rowSubvalue)
                .foregroundStyle(Color.textSecondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Space.margin)
    }

    /// "1,250.5" for a typed "1250.5" — grouping for display only; `amountText`
    /// itself stays the plain decimal string the order is sent with.
    private var groupedAmount: String {
        let parts = amountText.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Decimal(string: String(parts.first ?? "0")) ?? 0
        let grouped = NSDecimalNumber(decimal: whole).intValue.formatted(.number.grouping(.automatic))
        return parts.count > 1 ? grouped + "." + parts[1] : grouped
    }

    private var estimateLine: String {
        if side == .buy {
            if let quote { return "≈ \(PriceFormat.quantity(quote.outAmount)) \(tokenSymbol)" }
            let amount = Decimal(string: amountText) ?? 0
            guard let priceUsd, priceUsd > 0 else { return "≈ 0 \(tokenSymbol)" }
            return "≈ \(PriceFormat.quantity(amount / priceUsd)) \(tokenSymbol)"
        }
        guard let position, let percent = sellPercent else { return "≈ $0.00" }
        return "≈ " + PriceFormat.usd(TradeAmountMath.quickSellEstimate(positionValueUsd: position.valueUsd, percent: percent))
    }

    private var availableLine: some View {
        HStack(spacing: Space.s8) {
            Text(side == .buy
                 ? "\(PriceFormat.usd(cashUsd)) available"
                 : "\(position.map { PriceFormat.usd($0.valueUsd) } ?? "$0.00") held")
                .font(.caption13Digits)
                .foregroundStyle(Color.textSecondary)
            Text(portfolio.badge)
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, Space.s8)
                .padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(Color.appSeparator, lineWidth: 1))
        }
    }

    private var quickAmountRow: some View {
        HStack(spacing: Space.s8) {
            ForEach([25, 50, 75, 100], id: \.self) { percent in
                let isDisabled = isBuyQuickAmountDisabled(percent)
                Chip(title: percent == 100 ? "Max" : "\(percent)%", isSelected: isQuickAmountSelected(percent)) {
                    applyQuickAmount(percent)
                }
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.35 : 1)
            }
        }
    }

    /// A buy chip that would land on $0.00 (no cash, or cash too small for this
    /// percent to round to a cent) is a no-op if tapped — disable it rather than let
    /// it silently do nothing.
    private func isBuyQuickAmountDisabled(_ percent: Int) -> Bool {
        guard side == .buy else { return false }
        return TradeAmountMath.quickBuyAmount(cashUsd: cashUsd, percent: percent) == 0
    }

    private func isQuickAmountSelected(_ percent: Int) -> Bool {
        if side == .sell { return sellPercent == percent }
        guard cashUsd > 0, let value = Decimal(string: amountText) else { return false }
        return value == TradeAmountMath.quickBuyAmount(cashUsd: cashUsd, percent: percent)
    }

    private func applyQuickAmount(_ percent: Int) {
        if side == .sell {
            sellPercent = percent
        } else {
            let target = TradeAmountMath.quickBuyAmount(cashUsd: cashUsd, percent: percent)
            amountText = NSDecimalNumber(decimal: target).stringValue
        }
        requestQuote()
    }

    private var canSubmit: Bool {
        guard let id = portfolio.portfolioId, !id.isEmpty else { return false }
        if side == .buy { return Decimal(string: amountText).map { $0 > 0 } ?? false }
        return sellPercent != nil
    }

    // MARK: - Networking

    private func requestQuote() {
        quoteTask?.cancel()
        guard canSubmit, let portfolioId = portfolio.portfolioId else {
            quote = nil
            return
        }
        quoteTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            isQuoting = true
            errorMessage = nil
            do {
                quote = try await PaperAPI.quote(portfolioId: portfolioId, body: makeBody())
            } catch let error as APIError {
                errorMessage = portfolio.message(for: error) ?? error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isQuoting = false
        }
    }

    private func showAfterWinPaywall() {
        paywallReason = .afterWin
        showsPaywall = true
    }

    private func execute() async {
        guard let portfolioId = portfolio.portfolioId else { return }
        isExecuting = true
        errorMessage = nil
        // What the position cost, captured before the sell changes it.
        let averageCost = position?.avgCostUsd
        do {
            let result = try await PaperAPI.execute(portfolioId: portfolioId, body: makeBody())
            soldAverageCost = side == .sell ? averageCost : nil
            if portfolio.isMain, side == .buy { FreeTier.shared.recordTrade() }
            offersProAfterWin = portfolio.isMain
                && result.trade.side == .sell
                && averageCost.map { result.fill.fillPriceUsd > $0 } == true
                && FreeTier.shared.isLimited
            fillResult = result
            Haptics.success()
            await portfolio.refreshAfterTrade()
            let soldAtProfit = result.trade.side == .sell
                && averageCost.map { result.fill.fillPriceUsd > $0 } == true
            if ReviewPrompt.shouldRequest(afterProfit: soldAtProfit) {
                ReviewPrompt.markRequested()
                // Let the fill confirmation land first.
                try? await Task.sleep(for: .seconds(1.5))
                requestReview()
            }
            // A trade is when price alerts start to matter; iOS only ever shows
            // this prompt once, so in practice it's after the first one.
            await PushRegistrar.shared.requestPermissionIfNeeded()
        } catch let error as APIError {
            Haptics.error()
            errorMessage = portfolio.message(for: error) ?? error.errorDescription
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isExecuting = false
    }

    /// The trade card for a sell: entry at the average cost before the sell, exit
    /// at the fill. Nil for a buy, or when the entry wasn't known.
    private func shareCard(for result: ExecutePaperTradeResponse) -> TradeShareCardModel? {
        guard result.trade.side == .sell, let entry = soldAverageCost else { return nil }
        return TradeShareCardModel(
            mint: mint,
            symbol: tokenSymbol,
            entryPriceUsd: entry,
            currentPriceUsd: result.fill.fillPriceUsd,
            isClosed: true
        )
    }

    private func makeBody() -> ExecutePaperTradeBody {
        var body = ExecutePaperTradeBody(tokenMint: mint, side: side)
        if side == .buy {
            body.notionalUsd = amountText
        } else {
            body.sellPercent = sellPercent
        }
        if let price = quote?.priceUsd {
            body.expectedPriceUsd = NSDecimalNumber(decimal: price).stringValue
        }
        return body
    }
}

private struct FillConfirmationView: View {
    let result: ExecutePaperTradeResponse
    let symbol: String
    var shareCard: TradeShareCardModel? = nil
    var shareSubjectPath: String? = nil
    /// Set after a profitable sell on the free tier.
    var onSeePro: (() -> Void)? = nil
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Space.s24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.positive)
            Text(result.trade.side == .buy ? "Bought \(symbol)" : "Sold \(symbol)")
                .font(.appLargeTitle)
                .foregroundStyle(Color.textPrimary)
            StatGrid(items: [
                StatItem(label: "Filled at", value: PriceFormat.price(result.fill.fillPriceUsd)),
                StatItem(label: "Amount", value: PriceFormat.usd(result.trade.valueUsd)),
                StatItem(label: "Quantity", value: PriceFormat.quantity(result.trade.qty)),
                StatItem(label: "Cash balance", value: PriceFormat.usd(result.cashUsd)),
            ])
            Spacer()
            if let shareCard {
                TradeShareButton(model: shareCard)
                    .buttonStyle(.secondary)
            } else if let shareSubjectPath {
                // No entry price to draw a card from: fall back to the server's link card.
                ShareCardButton(subjectPath: shareSubjectPath)
                    .buttonStyle(.secondary)
            }
            if let onSeePro {
                Button("Trade without limits with Pro", action: onSeePro)
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("trade.afterWinPro")
            }
            Button("Done", action: onDone)
                .buttonStyle(.primary)
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.s8)
    }
}

/// In place of the buy ticket once the day's free buys are used. Says when they
/// come back and that selling still works, so it reads as a limit, not a lockout.
private struct OutOfFreeTradesView: View {
    let onSeePro: () -> Void

    var body: some View {
        VStack(spacing: Space.s24) {
            Spacer()
            Image(systemName: "hourglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.accent)
            Text("You've used today's \(FreeTier.freeTradesPerDay) free buys")
                .font(.appLargeTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textPrimary)
            Text("They come back tomorrow. Selling is always free. Pro buys without limits.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button("See Pro", action: onSeePro)
                .buttonStyle(.accent)
                .accessibilityIdentifier("trade.outOfTrades.seePro")
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.s8)
    }
}

/// A 3×4 keypad that edits a plain decimal string: digits, one decimal point, at
/// most two decimals, a sane length cap, and delete. Borderless keys with a press
/// state and a light haptic.
struct NumericKeypad: View {
    @Binding var text: String

    private let keys: [String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "delete"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: 0) {
            ForEach(keys, id: \.self) { key in
                Button {
                    Haptics.tap()
                    press(key)
                } label: {
                    Group {
                        if key == "delete" {
                            Image(systemName: "delete.left")
                                .font(.title2)
                        } else {
                            Text(key)
                                .font(.title.weight(.medium))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(KeypadKeyStyle())
                .accessibilityLabel(key == "delete" ? "Delete" : key)
            }
        }
    }

    private func press(_ key: String) {
        switch key {
        case "delete":
            if !text.isEmpty { text.removeLast() }
        case ".":
            guard !text.contains(".") else { return }
            text = text.isEmpty ? "0." : text + "."
        default:
            if let dot = text.firstIndex(of: "."), text.distance(from: dot, to: text.endIndex) > 2 { return }
            guard text.count < 10 else { return }
            text = (text == "0") ? key : text + key
        }
    }
}

struct KeypadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.appFill.opacity(configuration.isPressed ? 1 : 0))
                    .frame(width: 64, height: 64)
            )
            .pressEffect(configuration.isPressed)
    }
}
