import SwiftUI

/// Shown once on first launch, before the paywall. Each page leads with a small
/// animated scene built from the app's own visual language (glass cards, candles,
/// the podium) rather than a lone SF Symbol, over an aurora that shifts hue per page.
/// `RootView` owns the `hasSeenOnboarding` flag; this view only reports completion.
struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            art: .balance,
            eyebrow: "PRACTICE CASH",
            headline: "Start with $10,000.\nKeep every lesson.",
            detail: "Real market prices, zero real money. Make the mistakes here, not with your savings.",
            colors: [CookedColor.Prism.indigo, CookedColor.Brand.fill, CookedColor.Prism.cyan]
        ),
        OnboardingPage(
            art: .chart,
            eyebrow: "LIVE MARKETS",
            headline: "Read the chart.\nMake the call.",
            detail: "Candlesticks on live data, one-tap buys and sells, fills in under a second.",
            colors: [CookedColor.Prism.teal, CookedColor.Terminal.buy, CookedColor.Prism.sky]
        ),
        OnboardingPage(
            art: .podium,
            eyebrow: "LEADERBOARD",
            headline: "Climb the ranks.\nProve your edge.",
            detail: "Track your P&L, win rate and drawdown, then see how you stack up this month.",
            colors: [CookedColor.Prism.amber, CookedColor.Brand.dangerFill, CookedColor.Prism.indigo]
        ),
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            AmbientBackground(colors: pages[page].colors, base: CookedColor.Product.graphite)
                .animation(.easeInOut(duration: 0.8), value: page)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item, isActive: page == index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                    .padding(.top, CookedSpacing.md)

                actionButton
                    .padding(.horizontal, CookedSpacing.xl)
                    .padding(.top, CookedSpacing.xl)
                    .padding(.bottom, CookedSpacing.lg)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageIndicator: some View {
        HStack(spacing: CookedSpacing.xs) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.white : Color.white.opacity(0.22))
                    .frame(width: index == page ? 24 : 7, height: 7)
            }
        }
        .animation(CookedMotion.travel, value: page)
    }

    private var actionButton: some View {
        Button {
            Haptics.tap()
            if isLastPage {
                onFinished()
            } else {
                withAnimation(CookedMotion.travel) { page += 1 }
            }
        } label: {
            HStack(spacing: CookedSpacing.xs) {
                Text(isLastPage ? "Get Started" : "Next")
                Image(systemName: isLastPage ? "sparkles" : "arrow.right")
                    .font(.system(size: CookedIconSize.sm, weight: .bold))
            }
        }
        .buttonStyle(.cookedPrimary)
        .accessibilityIdentifier(isLastPage ? "onboarding.getStarted" : "onboarding.next")
    }
}

private enum OnboardingArt {
    case balance, chart, podium
}

private struct OnboardingPage {
    let art: OnboardingArt
    let eyebrow: String
    let headline: String
    let detail: String
    let colors: [Color]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool

    var body: some View {
        VStack(spacing: CookedSpacing.xl) {
            Spacer(minLength: CookedSpacing.md)

            Group {
                switch page.art {
                case .balance: BalanceCardArt(isActive: isActive)
                case .chart: LiveChartArt(isActive: isActive)
                case .podium: PodiumArt(isActive: isActive)
                }
            }
            .frame(height: 330)

            VStack(spacing: CookedSpacing.sm) {
                Text(page.eyebrow)
                    .font(CookedFont.label(12))
                    .tracking(1.6)
                    .foregroundStyle(page.colors[1])

                Text(page.headline)
                    .displayTextStyle(size: 30)
                    .foregroundStyle(CookedColor.Product.chalk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.detail)
                    .font(CookedFont.body(16))
                    .foregroundStyle(CookedColor.Product.chalkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, CookedSpacing.xl)
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 16)
            .animation(CookedMotion.calm.delay(0.1), value: isActive)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Page 1: a floating glass balance card with orbiting coins

private struct BalanceCardArt: View {
    let isActive: Bool
    @State private var tilt = false

    var body: some View {
        ZStack {
            Circle()
                .fill(CookedColor.Brand.fill.opacity(0.35))
                .frame(width: 260, height: 260)
                .blur(radius: 60)

            CoinView(size: 58, symbol: "dollarsign")
                .offset(x: -128, y: -104)
                .floating(amplitude: 8, period: 3.2)
            CoinView(size: 42, symbol: "chart.line.uptrend.xyaxis")
                .offset(x: 134, y: -72)
                .floating(amplitude: 6, period: 2.6, delay: 0.4)
            CoinView(size: 48, symbol: "bolt.fill")
                .offset(x: 118, y: 118)
                .floating(amplitude: 7, period: 3.6, delay: 0.8)

            card
                .rotation3DEffect(.degrees(tilt ? -8 : 8), axis: (x: 0.4, y: 1, z: 0), perspective: 0.6)
                .floating(amplitude: 5, period: 4)
                .scaleEffect(isActive ? 1 : 0.9)
                .animation(CookedMotion.sheet, value: isActive)
        }
        .onAppear {
            guard AmbientMotion.isEnabled else { return }
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { tilt = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: CookedSpacing.md) {
            HStack {
                Text("Cooked Paper")
                    .font(CookedFont.label(13))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Image(systemName: "wave.3.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            Text("PAPER BALANCE")
                .font(CookedFont.caption(10))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.65))
            RollingNumber(
                value: isActive ? 10_000 : 0,
                format: { "$" + $0.formatted(.number.precision(.fractionLength(2))) },
                font: CookedFont.priceDisplay(34),
                color: .white
            )
            HStack(spacing: CookedSpacing.xs) {
                ChangePill(value: 0, font: CookedFont.priceSmall(11))
                Text("ready to trade")
                    .font(CookedFont.caption())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(CookedSpacing.lg)
        .frame(width: 280, height: 176)
        .background(
            LinearGradient(
                colors: [CookedColor.Prism.indigo.opacity(0.55), CookedColor.Brand.fill.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: CookedRadius.xl, style: .continuous)
        )
        .glassPanel(cornerRadius: CookedRadius.xl, tint: CookedColor.Brand.fill)
        .shineSweep(cornerRadius: CookedRadius.xl)
        .shadow(color: CookedColor.Prism.indigo.opacity(0.5), radius: 30, y: 16)
    }
}

/// A glossy floating token — a gradient disc with a rim, a specular highlight and a
/// symbol stamped in, so it reads as a physical object.
struct CoinView: View {
    let size: CGFloat
    let symbol: String
    var colors: [Color] = [Color(hex: 0xFFE08A), Color(hex: 0xF0A020)]

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(.white.opacity(0.55), lineWidth: size * 0.05)
                .padding(size * 0.08)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.7), .clear], center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: size * 0.45))
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .heavy))
                .foregroundStyle(Color(hex: 0x7A4A00).opacity(0.85))
        }
        .frame(width: size, height: size)
        .shadow(color: colors[1].opacity(0.55), radius: size * 0.25, y: size * 0.12)
    }
}

// MARK: - Page 2: a candle chart that draws itself in

private struct LiveChartArt: View {
    let isActive: Bool
    @State private var revealed = false

    /// Hand-shaped series: a dip, a base, then a breakout — the story every
    /// first-time trader wants to see.
    private let candles: [(open: Double, close: Double, high: Double, low: Double)] = [
        (0.55, 0.5, 0.6, 0.45), (0.5, 0.42, 0.53, 0.38), (0.42, 0.36, 0.45, 0.31),
        (0.36, 0.4, 0.43, 0.33), (0.4, 0.34, 0.42, 0.3), (0.34, 0.38, 0.41, 0.32),
        (0.38, 0.46, 0.49, 0.36), (0.46, 0.44, 0.5, 0.41), (0.44, 0.55, 0.58, 0.43),
        (0.55, 0.62, 0.66, 0.52), (0.62, 0.58, 0.65, 0.55), (0.58, 0.7, 0.73, 0.57),
        (0.7, 0.78, 0.82, 0.68), (0.78, 0.9, 0.94, 0.76),
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(CookedColor.Terminal.buy.opacity(0.28))
                .frame(width: 280, height: 280)
                .blur(radius: 60)

            VStack(alignment: .leading, spacing: CookedSpacing.sm) {
                HStack(spacing: CookedSpacing.xs) {
                    TokenAvatar(seed: "DemoToken", label: "WIF", size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("WIF")
                            .font(CookedFont.headline(15))
                            .foregroundStyle(.white)
                        Text("dogwifhat")
                            .font(CookedFont.caption())
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    ChangePill(value: Decimal(string: "18.42"))
                }

                GeometryReader { geo in
                    ZStack {
                        candleLayer(size: geo.size)
                        trendLine(size: geo.size)
                            .trim(from: 0, to: revealed ? 1 : 0)
                            .stroke(
                                LinearGradient(colors: [CookedColor.Prism.teal, CookedColor.Terminal.buy], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: CookedColor.Terminal.buy.opacity(0.8), radius: 6)
                    }
                }
                .frame(height: 150)
            }
            .padding(CookedSpacing.md)
            .frame(width: 300)
            .glassPanel(cornerRadius: CookedRadius.xl)
            .shadow(color: .black.opacity(0.4), radius: 30, y: 18)
            .floating(amplitude: 5, period: 4.2)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Bought 820 WIF")
            }
            .font(CookedFont.label(13))
            .foregroundStyle(CookedColor.Brand.onFill)
            .padding(.horizontal, CookedSpacing.sm)
            .padding(.vertical, CookedSpacing.xs)
            .background(CookedColor.Terminal.buy, in: Capsule())
            .shadow(color: CookedColor.Terminal.buy.opacity(0.6), radius: 14, y: 6)
            .offset(x: 70, y: 140)
            .scaleEffect(revealed ? 1 : 0.4)
            .opacity(revealed ? 1 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.9), value: revealed)
        }
        .onAppear { reveal() }
        .onChange(of: isActive) { _, active in if active { reveal() } }
    }

    private func reveal() {
        guard isActive else { return }
        if AmbientMotion.isEnabled {
            revealed = false
            withAnimation(.easeOut(duration: 1.4).delay(0.2)) { revealed = true }
        } else {
            revealed = true
        }
    }

    private func candleLayer(size: CGSize) -> some View {
        let slot = size.width / CGFloat(candles.count)
        return ZStack(alignment: .topLeading) {
            ForEach(candles.indices, id: \.self) { index in
                let candle = candles[index]
                let isUp = candle.close >= candle.open
                let color = isUp ? CookedColor.Terminal.buy : CookedColor.Terminal.sell
                let bodyTop = size.height * (1 - max(candle.open, candle.close))
                let bodyHeight = max(3, size.height * abs(candle.close - candle.open))
                let wickTop = size.height * (1 - candle.high)
                let wickHeight = size.height * (candle.high - candle.low)
                let x = slot * CGFloat(index) + slot / 2

                ZStack(alignment: .top) {
                    Capsule()
                        .fill(color.opacity(0.7))
                        .frame(width: 1.5, height: wickHeight)
                        .offset(y: wickTop - bodyTop)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(width: slot * 0.55, height: bodyHeight)
                }
                .frame(width: slot, alignment: .top)
                .position(x: x, y: bodyTop + bodyHeight / 2)
                .opacity(revealed ? 1 : 0)
                .scaleEffect(y: revealed ? 1 : 0.2, anchor: .bottom)
                .animation(CookedMotion.calm.delay(0.05 * Double(index)), value: revealed)
            }
        }
    }

    private func trendLine(size: CGSize) -> Path {
        let slot = size.width / CGFloat(candles.count)
        return Path { path in
            for (index, candle) in candles.enumerated() {
                let point = CGPoint(
                    x: slot * CGFloat(index) + slot / 2,
                    y: size.height * (1 - (candle.open + candle.close) / 2)
                )
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

// MARK: - Page 3: a podium that rises, with a trophy on top

private struct PodiumArt: View {
    let isActive: Bool
    @State private var risen = false
    @State private var trophyBounce = 0

    private let places: [(rank: Int, name: String, height: CGFloat, color: Color)] = [
        (2, "solsniper", 110, Color(hex: 0xC9D3E0)),
        (1, "you", 150, Color(hex: 0xFFD166)),
        (3, "moonboi", 84, Color(hex: 0xE3A36F)),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(CookedColor.Prism.amber.opacity(0.3))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(y: -60)

            sparkles

            HStack(alignment: .bottom, spacing: CookedSpacing.sm) {
                ForEach(places.indices, id: \.self) { index in
                    let place = places[index]
                    VStack(spacing: CookedSpacing.xs) {
                        if place.rank == 1 {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(colors: [Color(hex: 0xFFE9A8), Color(hex: 0xF0A020)], startPoint: .top, endPoint: .bottom)
                                )
                                .shadow(color: Color(hex: 0xF0A020).opacity(0.7), radius: 16)
                                .symbolEffect(.bounce, value: trophyBounce)
                                .floating(amplitude: 4, period: 2.8)
                        }
                        TokenAvatar(seed: place.name, label: place.name, size: place.rank == 1 ? 50 : 40)
                            .overlay(Circle().strokeBorder(place.color, lineWidth: 2))
                        Text(place.name)
                            .font(CookedFont.label(12))
                            .foregroundStyle(.white.opacity(0.85))
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: CookedRadius.md, style: .continuous)
                                .fill(
                                    LinearGradient(colors: [place.color.opacity(0.55), place.color.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                                )
                            Text("\(place.rank)")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.top, CookedSpacing.sm)
                        }
                        .frame(width: 84, height: risen ? place.height : 12)
                        .glassPanel(cornerRadius: CookedRadius.md, tint: place.color)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.12 * Double(index)), value: risen)
                    }
                }
            }
            .padding(.bottom, CookedSpacing.md)
        }
        .onAppear { rise() }
        .onChange(of: isActive) { _, active in if active { rise() } }
    }

    private var sparkles: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                let angle = Double(index) / 7 * 2 * .pi
                Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "star.fill")
                    .font(.system(size: index.isMultiple(of: 3) ? 16 : 10, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFFE9A8).opacity(0.85))
                    .offset(x: CGFloat(cos(angle)) * 130, y: CGFloat(sin(angle)) * 70 - 150)
                    .scaleEffect(risen ? 1 : 0.2)
                    .opacity(risen ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.5 + 0.05 * Double(index)), value: risen)
                    .floating(amplitude: 4, period: 2 + Double(index) * 0.3, delay: Double(index) * 0.2)
            }
        }
    }

    private func rise() {
        guard isActive else { return }
        if AmbientMotion.isEnabled {
            risen = false
            withAnimation { risen = true }
            trophyBounce += 1
        } else {
            risen = true
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
