import Foundation
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

    @Environment(\.dismiss) private var dismiss
    private let portfolioStore = PortfolioStore.shared

    @State private var amountText = ""
    @State private var sellPercent: Int?
    @State private var quote: PaperQuoteResponse?
    @State private var isQuoting = false
    @State private var isExecuting = false
    @State private var errorMessage: String?
    @State private var fillResult: ExecutePaperTradeResponse?
    @State private var quoteTask: Task<Void, Never>?
    @FocusState private var isAmountFieldFocused: Bool

    private var cashUsd: Decimal { portfolioStore.snapshot?.cashUsd ?? 0 }
    private var position: PaperPosition? {
        portfolioStore.snapshot?.positions.first { $0.tokenMint == mint }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CookedColor.Terminal.bgBase.ignoresSafeArea()

                if let fillResult {
                    FillConfirmationView(result: fillResult, symbol: tokenSymbol) { dismiss() }
                } else {
                    form
                }
            }
            .navigationTitle("\(side == .buy ? "Buy" : "Sell") \(tokenSymbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(CookedColor.Terminal.bgBase)
    }

    private var form: some View {
        VStack(spacing: CookedSpacing.lg) {
            VStack(spacing: CookedSpacing.xs) {
                Text(side == .buy ? "Amount to spend" : "Amount to sell")
                    .font(CookedFont.caption())
                    .foregroundStyle(CookedColor.Terminal.textMuted)

                if side == .buy {
                    HStack {
                        Text("$")
                            .font(CookedFont.priceDisplay(36))
                            .foregroundStyle(CookedColor.Terminal.textMuted)
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(CookedFont.priceDisplay(36))
                            .foregroundStyle(CookedColor.Terminal.textPrimary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 160)
                            .focused($isAmountFieldFocused)
                            .onChange(of: amountText) { _, _ in requestQuote() }
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { isAmountFieldFocused = false }
                                }
                            }
                    }
                } else {
                    Text(sellPercent.map { "\($0)%" } ?? "—")
                        .font(CookedFont.priceDisplay(36))
                        .foregroundStyle(CookedColor.Terminal.textPrimary)
                    if let position, let percent = sellPercent {
                        let estimate = TradeAmountMath.quickSellEstimate(positionValueUsd: position.valueUsd, percent: percent)
                        Text("≈ \(estimate.usdString())")
                            .font(CookedFont.caption())
                            .foregroundStyle(CookedColor.Terminal.textMuted)
                    }
                }
            }
            .padding(.top, CookedSpacing.lg)

            quickAmountRow

            if let position, side == .sell {
                Text("You hold \(position.qty.formatted()) \(tokenSymbol) worth \(position.valueUsd.usdString())")
                    .font(CookedFont.caption())
                    .foregroundStyle(CookedColor.Terminal.textMuted)
            }

            if let quote {
                quotePreview(quote)
            } else if isQuoting {
                ProgressView().tint(CookedColor.Brand.fill)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(CookedFont.caption())
                    .foregroundStyle(CookedColor.Terminal.sell)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CookedSpacing.lg)
            }

            Spacer()

            Button {
                Task { await execute() }
            } label: {
                if isExecuting {
                    ProgressView().tint(CookedColor.Brand.onFill)
                } else {
                    Text("Review \(side == .buy ? "Buy" : "Sell")")
                }
            }
            .buttonStyle(.cookedPrimary(destructive: side == .sell, enabled: canSubmit))
            .disabled(!canSubmit || isExecuting)
            .padding(.horizontal, CookedSpacing.lg)
            .padding(.bottom, CookedSpacing.lg)
        }
    }

    private var quickAmountRow: some View {
        HStack(spacing: CookedSpacing.xs) {
            ForEach([25, 50, 75, 100], id: \.self) { percent in
                let isDisabled = isBuyQuickAmountDisabled(percent)
                CookedChip(title: "\(percent)%", isSelected: isQuickAmountSelected(percent)) {
                    applyQuickAmount(percent)
                }
                .disabled(isDisabled)
                // Same 0.4 dimming `PrimaryButtonStyle` uses for its own disabled state.
                .opacity(isDisabled ? 0.4 : 1)
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

    private func quotePreview(_ quote: PaperQuoteResponse) -> some View {
        CookedCard {
            VStack(spacing: CookedSpacing.xs) {
                previewRow("Price", quote.priceUsd.usdString(fractionDigits: quote.priceUsd < 1 ? 6 : 2))
                previewRow("Price impact", quote.priceImpactPct.signedPercentString())
                previewRow("You'll receive", "\(quote.outAmount.formatted()) \(side == .buy ? tokenSymbol : "USD")")

                ForEach(quote.guidance.warnings) { warning in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: CookedIconSize.xs))
                            .foregroundStyle(CookedColor.Terminal.warn)
                        Text(warning.message)
                            .font(CookedFont.caption())
                            .foregroundStyle(CookedColor.Terminal.textSecondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, CookedSpacing.lg)
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(CookedFont.caption()).foregroundStyle(CookedColor.Terminal.textMuted)
            Spacer()
            Text(value).font(CookedFont.priceSmall()).foregroundStyle(CookedColor.Terminal.textPrimary)
        }
    }

    private var canSubmit: Bool {
        guard let id = SessionStore.shared.activePortfolioId, !id.isEmpty else { return false }
        if side == .buy { return Decimal(string: amountText).map { $0 > 0 } ?? false }
        return sellPercent != nil
    }

    // MARK: - Networking

    private func requestQuote() {
        quoteTask?.cancel()
        guard canSubmit, let portfolioId = SessionStore.shared.activePortfolioId else {
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
                errorMessage = error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isQuoting = false
        }
    }

    private func execute() async {
        guard let portfolioId = SessionStore.shared.activePortfolioId else { return }
        isExecuting = true
        errorMessage = nil
        do {
            let result = try await PaperAPI.execute(portfolioId: portfolioId, body: makeBody())
            fillResult = result
            Haptics.success()
            await portfolioStore.refreshAfterTrade()
        } catch let error as APIError {
            Haptics.error()
            errorMessage = error.errorDescription
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isExecuting = false
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
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: CookedSpacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: CookedIconSize.hero))
                .foregroundStyle(CookedColor.Terminal.buy)
            Text(result.trade.side == .buy ? "Bought \(symbol)" : "Sold \(symbol)")
                .font(CookedFont.title())
                .foregroundStyle(CookedColor.Terminal.textPrimary)
            Text("Filled at \(result.fill.fillPriceUsd.usdString(fractionDigits: result.fill.fillPriceUsd < 1 ? 6 : 2))")
                .font(CookedFont.body())
                .foregroundStyle(CookedColor.Terminal.textSecondary)
            Text("Cash balance: \(result.cashUsd.usdString())")
                .font(CookedFont.caption())
                .foregroundStyle(CookedColor.Terminal.textMuted)
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.cookedPrimary)
                .padding(.horizontal, CookedSpacing.lg)
                .padding(.bottom, CookedSpacing.lg)
        }
    }
}
