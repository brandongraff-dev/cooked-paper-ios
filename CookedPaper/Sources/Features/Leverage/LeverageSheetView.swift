import Foundation
import SwiftUI

/// Opens a leveraged paper position: direction, multiple, and the margin to put up.
/// The multiples, directions and minimum margin come from `GET /paper/leverage/config`
/// (`LeverageConfigStore`), falling back to long/short at 2x/5x/10x. Everything that matters — entry, size, liquidation price — comes from the
/// server's quote against the live price; nothing is estimated on the device.
struct LeverageSheetView: View {
    let mint: String
    let tokenSymbol: String
    /// The portfolio the position opens in: the main one unless a duel passes its
    /// own (see `TradePortfolioContext`).
    var portfolio: TradePortfolioContext = .main

    @Environment(\.dismiss) private var dismiss
    private let configStore = LeverageConfigStore.shared

    @State private var direction: LeverageDirection = .long
    @State private var leverage = 5
    @State private var amountText = ""
    @State private var quote: PaperLeverageQuoteResponse?
    @State private var isQuoting = false
    @State private var isExecuting = false
    @State private var errorMessage: String?
    @State private var result: PaperLeveragedMutationResponse?
    @State private var quoteTask: Task<Void, Never>?
    /// One id per order the person means to place; reused if a request is retried.
    @State private var clientOrderId = UUID().uuidString

    private var cashUsd: Decimal { portfolio.snapshot?.cashUsd ?? 0 }
    private var margin: Decimal { Decimal(string: amountText) ?? 0 }
    private var isBelowMinimum: Bool {
        guard let minimum = configStore.minMarginUsd else { return false }
        return margin > 0 && margin < minimum
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    LeverageOpenedView(result: result) { dismiss() }
                } else {
                    form
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appSurfaceElevated)
            .navigationTitle("Leverage \(tokenSymbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .task {
            await configStore.loadIfNeeded()
            applyConfig()
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        VStack(spacing: Space.s16) {
            directionPicker
            leveragePicker

            Spacer(minLength: 0)
            amountDisplay
            Spacer(minLength: 0)

            summary
            if let message = errorMessage ?? quote?.ineligibleMessage {
                Text(message)
                    .font(.caption13)
                    .foregroundStyle(Color.negative)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NumericKeypad(text: $amountText)
            Button {
                Task { await open() }
            } label: {
                if isExecuting {
                    ProgressView().tint(Color.inverseText)
                } else {
                    Text(margin > 0 ? "Open \(leverage)x \(direction.title) · \(PriceFormat.usd(margin))" : "Enter margin")
                }
            }
            .buttonStyle(.primary)
            .disabled(!canSubmit || isExecuting)
            .accessibilityIdentifier("leverage.open")
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s8)
        .padding(.bottom, Space.s8)
        .onChange(of: amountText) { _, _ in inputsChanged() }
        .onChange(of: leverage) { _, _ in inputsChanged() }
        .onChange(of: direction) { _, _ in inputsChanged() }
    }

    // MARK: - Pickers

    private var directionPicker: some View {
        HStack(spacing: Space.s4) {
            ForEach(configStore.directions) { option in
                Segment(title: option.title, isSelected: direction == option) { direction = option }
                    .accessibilityIdentifier("leverage.direction.\(option.rawValue)")
            }
        }
        .padding(Space.s4)
        .background(Color.appSurface, in: Capsule())
    }

    private var leveragePicker: some View {
        HStack(spacing: Space.s8) {
            ForEach(configStore.leverageOptions, id: \.self) { option in
                Button {
                    guard leverage != option else { return }
                    Haptics.selection()
                    leverage = option
                } label: {
                    Text("\(option)x")
                        .font(.rowTitle)
                        .monospacedDigit()
                        .foregroundStyle(leverage == option ? Color.inverseText : Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(leverage == option ? Color.inverseFill : Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                }
                .buttonStyle(.pressable)
                .animation(Motion.standard, value: leverage)
                .accessibilityIdentifier("leverage.multiple.\(option)")
            }
        }
    }

    // MARK: - Amount

    private var amountDisplay: some View {
        VStack(spacing: Space.s8) {
            Text(amountText.isEmpty ? "$0" : "$" + amountText)
                .font(.amountEntry)
                .tracking(-1)
                .foregroundStyle(amountText.isEmpty ? Color.textTertiary : Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(Motion.press, value: amountText)
            HStack(spacing: Space.s8) {
                Text("Margin · \(PriceFormat.usd(cashUsd)) available")
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
    }

    /// Size, entry and liquidation from the live quote.
    private var summary: some View {
        VStack(spacing: Space.s12) {
            summaryRow("Position size", quote.map { PriceFormat.usd($0.notionalUsd) } ?? (margin > 0 ? PriceFormat.usd(margin * Decimal(leverage)) : "—"))
            summaryRow("Entry price", quote.map { "≈ " + PriceFormat.price($0.estEntryPriceUsd) } ?? "—")
            summaryRow("Liquidation price", quote.map { PriceFormat.price($0.liquidationPriceUsd) } ?? "—")
            Text(liquidationSentence)
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())
        }
        .padding(Space.s16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .redacted(reason: isQuoting && quote == nil ? .placeholder : [])
    }

    private var liquidationSentence: String {
        guard let quote else {
            return "At \(leverage)x, a \(direction == .long ? "drop" : "rise") of about \(100 / leverage)% loses the whole margin."
        }
        let move = abs(quote.liquidationMovePct).formatted(.number.precision(.fractionLength(1)))
        return "Liquidated if \(tokenSymbol) \(direction == .long ? "falls" : "rises") \(move)% from here. Most you can lose is your margin."
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.rowValue)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
        }
    }

    private var canSubmit: Bool {
        guard let id = portfolio.portfolioId, !id.isEmpty else { return false }
        guard margin > 0, margin <= cashUsd, !isBelowMinimum else { return false }
        return quote?.eligible ?? true
    }

    // MARK: - Networking

    private func inputsChanged() {
        clientOrderId = UUID().uuidString
        if margin > cashUsd && margin > 0 {
            errorMessage = "That's more than your paper cash."
        } else if isBelowMinimum, let minimum = configStore.minMarginUsd {
            errorMessage = "The minimum margin is \(PriceFormat.usd(minimum))."
        } else {
            errorMessage = nil
        }
        requestQuote()
    }

    /// Keeps the selection inside what the server offers once its config arrives.
    private func applyConfig() {
        if !configStore.leverageOptions.contains(leverage) {
            leverage = configStore.defaultLeverage
        }
        if !configStore.directions.contains(direction), let first = configStore.directions.first {
            direction = first
        }
    }

    private func requestQuote() {
        quoteTask?.cancel()
        guard margin > 0, !isBelowMinimum, let portfolioId = portfolio.portfolioId else {
            quote = nil
            return
        }
        let body = PaperLeverageQuoteBody(tokenMint: mint, direction: direction, leverage: leverage, marginUsd: amountText)
        quoteTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isQuoting = true
            do {
                let fresh = try await PaperAPI.leverageQuote(portfolioId: portfolioId, body: body)
                guard !Task.isCancelled else { return }
                withAnimation(Motion.standard) { quote = fresh }
            } catch {
                guard !Task.isCancelled else { return }
                quote = nil
                errorMessage = message(for: error)
            }
            isQuoting = false
        }
    }

    private func open() async {
        guard let portfolioId = portfolio.portfolioId else { return }
        isExecuting = true
        errorMessage = nil
        var body = OpenPaperLeveragedBody(
            tokenMint: mint,
            direction: direction,
            leverage: leverage,
            marginUsd: amountText,
            clientOrderId: clientOrderId
        )
        if let quote {
            body.expectedPriceUsd = NSDecimalNumber(decimal: quote.midPriceUsd).stringValue
            body.maxSlippageBps = 300
        }
        do {
            let opened = try await PaperAPI.openLeveraged(portfolioId: portfolioId, body: body)
            Haptics.success()
            withAnimation(Motion.standard) { result = opened }
            await portfolio.refreshAfterTrade()
        } catch {
            Haptics.error()
            errorMessage = message(for: error)
            if (error as? APIError)?.reason == "price_moved" { requestQuote() }
        }
        isExecuting = false
    }

    private func message(for error: Error) -> String {
        if let duelMessage = portfolio.message(for: error) { return duelMessage }
        if let apiError = error as? APIError {
            if let reason = apiError.reason { return LeverageRefusal.message(for: reason) }
            return apiError.errorDescription ?? "Something went wrong."
        }
        return error.localizedDescription
    }
}

private struct LeverageOpenedView: View {
    let result: PaperLeveragedMutationResponse
    let onDone: () -> Void

    var body: some View {
        let position = result.position
        VStack(spacing: Space.s24) {
            Spacer()
            TokenAvatar(mint: position.tokenMint, symbol: position.token?.symbol, size: 56)
            VStack(spacing: Space.s8) {
                Text("\(position.label) \(position.symbol)")
                    .font(.appLargeTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Opened at \(PriceFormat.price(position.entryPriceUsd))")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
            }
            StatGrid(items: [
                StatItem(label: "Position size", value: PriceFormat.usd(position.notionalUsd)),
                StatItem(label: "Margin", value: PriceFormat.usd(position.marginUsd)),
                StatItem(label: "Liquidation price", value: PriceFormat.price(position.liquidationPriceUsd)),
                StatItem(label: "Cash balance", value: PriceFormat.usd(result.cashUsd)),
            ])
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.primary)
                .accessibilityIdentifier("leverage.done")
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.s8)
    }
}
