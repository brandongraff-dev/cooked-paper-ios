import SwiftUI

/// The Portfolio screen's compact "Cooked meter": a half-circle gauge with the
/// score, the tier name and a line of flavor. Tapping it opens `CookedMeterSheet`.
struct CookedMeterCard: View {
    let reading: CookedMeter.Reading
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Space.s16) {
                CookedMeterGauge(score: reading.score, size: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cooked meter")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                    HStack(spacing: Space.s4) {
                        Image(systemName: reading.tier.symbol)
                            .font(.subheadline.weight(.semibold))
                            .accessibilityHidden(true)
                        Text(reading.tier.title)
                            .font(.rowTitle)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.textPrimary)
                    Text(reading.tier.copy)
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .animation(Motion.standard, value: reading.tier)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Cooked meter, \(reading.score) out of 100, \(reading.tier.title)")
        .accessibilityHint("Shows what's driving the score")
        .accessibilityIdentifier("portfolio.cookedMeter")
    }
}

/// A half-circle gauge filling left to right with the score under it. Monochrome
/// on purpose: a white arc on the fill track; only the number turns red once it's
/// well done.
struct CookedMeterGauge: View {
    let score: Int
    var size: CGFloat = 72

    private var fraction: Double { Double(min(100, max(0, score))) / 100 }
    private var lineWidth: CGFloat { max(6, size * 0.1) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                HalfArc()
                    .stroke(Color.appFill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                HalfArc()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.textPrimary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            .padding(lineWidth / 2)

            Text("\(score)")
                .font(.system(size: size * 0.3, weight: .semibold).monospacedDigit())
                .foregroundStyle(score > 60 ? Color.negative : Color.textPrimary)
                .contentTransition(.numericText(value: Double(score)))
        }
        .frame(width: size, height: size * 0.62)
        .animation(Motion.standard, value: score)
        .accessibilityHidden(true)
    }
}

/// The top half of a circle inscribed in the rect's width, drawn left to right so
/// `trim(from: 0, to:)` fills it like a gauge.
private struct HalfArc: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return path
    }
}

/// What's cooking: the big gauge, the top one or two reasons, and a tip for
/// bringing the heat down.
struct CookedMeterSheet: View {
    let reading: CookedMeter.Reading

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s24) {
                    VStack(spacing: Space.s8) {
                        CookedMeterGauge(score: reading.score, size: 140)
                        HStack(spacing: Space.s8) {
                            Image(systemName: reading.tier.symbol)
                                .accessibilityHidden(true)
                            Text(reading.tier.title)
                        }
                        .font(.sectionHeader)
                        .foregroundStyle(Color.textPrimary)
                        Text(reading.tier.copy)
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(reading.score) out of 100, \(reading.tier.title). \(reading.tier.copy)")

                    VStack(alignment: .leading, spacing: Space.headerGap) {
                        SectionHeader(title: "What's cooking")
                        if reading.reasons.isEmpty {
                            Text("Nothing on the stove right now.")
                                .font(.rowSubtitle)
                                .foregroundStyle(Color.textSecondary)
                        } else {
                            VStack(alignment: .leading, spacing: Space.s12) {
                                ForEach(reading.reasons, id: \.self) { reason in
                                    HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                                        Image(systemName: "flame")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(Color.textTertiary)
                                            .accessibilityHidden(true)
                                        Text(reason)
                                            .font(.rowSubtitle)
                                            .foregroundStyle(Color.textPrimary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.headerGap) {
                        SectionHeader(title: "What lowers it")
                        Text(reading.tip)
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Paper · Simulated. Just for fun, not advice.")
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.s8)
            }
            .scrollIndicators(.hidden)
            .background(Color.appSurfaceElevated)
            .navigationTitle("Cooked meter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                        .accessibilityIdentifier("cookedMeter.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Previews

#if DEBUG
/// Steps through a few readings so the preview shows the animated transitions.
private struct CookedMeterCardPreview: View {
    @State private var index = 2

    private let readings: [CookedMeter.Reading] = [
        CookedMeter.reading(CookedMeter.Input(equityUsd: 10_000)),
        CookedMeter.Reading(
            score: 33,
            tier: .lightlyToasted,
            reasons: ["Leverage controls 49% of your equity"],
            tip: "Lower your leverage or close a leveraged position to take some heat off."
        ),
        // Roughly the DEBUG MockAPI portfolio.
        CookedMeter.reading(CookedMeter.Input(
            equityUsd: 11_291,
            holdings: [
                CookedMeter.Holding(symbol: "BONK", valueUsd: 2_129, costUsd: 1_650, unrealizedPnlUsd: 479, liquidityUsd: 9_120_443),
                CookedMeter.Holding(symbol: "WIF", valueUsd: 1_504, costUsd: 1_612, unrealizedPnlUsd: -108, liquidityUsd: 22_014_330),
                CookedMeter.Holding(symbol: "POPCAT", valueUsd: 1_204, costUsd: 1_010, unrealizedPnlUsd: 194, liquidityUsd: 6_120_300),
            ],
            leveraged: [
                CookedMeter.LeveragedHolding(symbol: "WIF", isLong: true, leverage: 5, notionalUsd: 2_500, marginUsd: 500, valueUsd: 628, unrealizedPnlUsd: 128, distanceToLiquidationPct: -23.1),
                CookedMeter.LeveragedHolding(symbol: "BONK", isLong: false, leverage: 10, notionalUsd: 3_000, marginUsd: 300, valueUsd: 215, unrealizedPnlUsd: -85, distanceToLiquidationPct: 5.9),
            ]
        )),
        CookedMeter.Reading(
            score: 92,
            tier: .fullyCooked,
            reasons: ["10x long WIF is 2% from liquidation", "88% of your portfolio is in WIF"],
            tip: "Add margin, cut the size, or close the position closest to liquidation."
        ),
    ]

    var body: some View {
        VStack(spacing: Space.s16) {
            CookedMeterCard(reading: readings[index]) {}
            Button("Next reading") {
                withAnimation(Motion.standard) { index = (index + 1) % readings.count }
            }
            .buttonStyle(.compact)
        }
        .padding(Space.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

#Preview("Cooked meter card") {
    CookedMeterCardPreview()
}

#Preview("Cooked meter sheet") {
    Color.appBackground
        .sheet(isPresented: .constant(true)) {
            CookedMeterSheet(reading: CookedMeter.Reading(
                score: 67,
                tier: .wellDone,
                reasons: ["5x long WIF is 9% from liquidation", "62% of your portfolio is in BONK"],
                tip: "Add margin, cut the size, or close the position closest to liquidation."
            ))
        }
}
#endif
