import Foundation
import SwiftUI

/// One open leveraged position: live P&L on margin, where it liquidates, and
/// closing all or part of it at the live price.
struct LeveragedPositionSheet: View {
    let positionId: String

    @Environment(\.dismiss) private var dismiss
    private let portfolioStore = PortfolioStore.shared

    @State private var closePercent = 100
    @State private var isClosing = false
    @State private var errorMessage: String?
    @State private var result: PaperLeveragedMutationResponse?

    private var position: PaperLeveragedPosition? {
        portfolioStore.snapshot?.leveragedPositions?.first { $0.id == positionId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    LeverageClosedView(result: result) { dismiss() }
                } else if let position {
                    details(position)
                } else {
                    EmptyStateView(symbol: "checkmark.circle", title: "Position closed", detail: "It no longer shows as open. Pull to refresh your portfolio.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appSurfaceElevated)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
        .presentationDragIndicator(.visible)
    }

    private func details(_ position: PaperLeveragedPosition) -> some View {
        VStack(alignment: .leading, spacing: Space.s24) {
            HStack(spacing: Metrics.avatarGap) {
                TokenAvatar(mint: position.tokenMint, symbol: position.token?.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.symbol)
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                    LeverageBadge(position: position)
                }
            }

            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Value")
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                Text(PriceFormat.usd(position.valueUsd))
                    .heroPriceStyle()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if let pnl = position.unrealizedPnlUsd {
                    Text("\(PriceFormat.signedUSD(pnl)) (\(PriceFormat.change(position.unrealizedReturnOnMarginPct))) on margin")
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.direction(pnl))
                } else {
                    Text("Unmeasured — no fresh price right now")
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            StatGrid(items: [
                StatItem(label: "Entry", value: PriceFormat.price(position.entryPriceUsd)),
                StatItem(label: "Mark", value: position.markPriceUsd.map(PriceFormat.price) ?? "—"),
                StatItem(label: "Liquidation", value: PriceFormat.price(position.liquidationPriceUsd)),
                StatItem(label: "Distance", value: position.distanceToLiquidationPct.map { PriceFormat.change($0) } ?? "—"),
                StatItem(label: "Margin", value: PriceFormat.usd(position.marginUsd)),
                StatItem(label: "Size", value: PriceFormat.usd(position.notionalUsd)),
            ])

            Spacer(minLength: 0)

            VStack(spacing: Space.s16) {
                HStack(spacing: Space.s8) {
                    ForEach([25, 50, 75, 100], id: \.self) { percent in
                        Chip(title: percent == 100 ? "All" : "\(percent)%", isSelected: closePercent == percent) {
                            closePercent = percent
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await close(position) }
                } label: {
                    if isClosing {
                        ProgressView().tint(Color.inverseText)
                    } else {
                        Text(closePercent == 100 ? "Close position" : "Close \(closePercent)%")
                    }
                }
                .buttonStyle(.primary)
                .disabled(isClosing)
                .accessibilityIdentifier("leverage.close")
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s8)
        .padding(.bottom, Space.s8)
    }

    private func close(_ position: PaperLeveragedPosition) async {
        guard let portfolioId = SessionStore.shared.activePortfolioId else { return }
        isClosing = true
        errorMessage = nil
        do {
            let closed = try await PaperAPI.closeLeveraged(
                portfolioId: portfolioId,
                positionId: position.id,
                body: ClosePaperLeveragedBody(closePercent: closePercent)
            )
            Haptics.success()
            withAnimation(Motion.standard) { result = closed }
        } catch let error as APIError where error.reason == "position_not_open" {
            // Liquidated (or closed elsewhere) in the meantime — say so plainly.
            Haptics.warning()
            errorMessage = "This position was already closed or liquidated."
        } catch let error as APIError {
            Haptics.error()
            errorMessage = error.reason.map(LeverageRefusal.message(for:)) ?? error.errorDescription
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        await portfolioStore.refreshAfterTrade()
        isClosing = false
    }
}

private struct LeverageClosedView: View {
    let result: PaperLeveragedMutationResponse
    let onDone: () -> Void

    var body: some View {
        let pnl = result.fill.realizedPnlUsd
        VStack(spacing: Space.s24) {
            Spacer()
            TokenAvatar(mint: result.position.tokenMint, symbol: result.position.token?.symbol, size: 56)
            VStack(spacing: Space.s8) {
                Text(PriceFormat.signedUSD(pnl))
                    .heroPriceStyle()
                    .foregroundStyle(Color.direction(pnl))
                // A close that lands past the liquidation price settles as a liquidation.
                Text("\(result.fill.kind == "liquidation" ? "Liquidated" : "Closed") \(result.position.label) \(result.position.symbol)")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
            }
            StatGrid(items: [
                StatItem(label: "Exit price", value: PriceFormat.price(result.fill.priceUsd)),
                StatItem(label: "Margin returned", value: PriceFormat.usd(max(0, result.fill.marginUsd + pnl))),
                StatItem(label: "Still open", value: result.position.status == .open ? PriceFormat.usd(result.position.marginUsd) + " margin" : "None"),
                StatItem(label: "Cash balance", value: PriceFormat.usd(result.cashUsd)),
            ])
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.primary)
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.s8)
    }
}

/// "5x Long" in a small neutral capsule. Direction is words, not color: green and
/// red are reserved for gains and losses.
struct LeverageBadge: View {
    let leverage: Int
    let direction: LeverageDirection

    init(position: PaperLeveragedPosition) {
        leverage = position.leverage
        direction = position.direction
    }

    init(leverage: Int, direction: LeverageDirection) {
        self.leverage = leverage
        self.direction = direction
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: direction == .long ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.bold))
            Text("\(leverage)x \(direction.title)")
                .font(.caption13.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, Space.s8)
        .padding(.vertical, 2)
        .background(Color.appFill, in: Capsule())
    }
}
