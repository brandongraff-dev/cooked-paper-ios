import Charts
import Foundation
import SwiftUI

/// A real stretch of market history, bundled with the app: WIF/USDT 1-minute
/// closes from Binance for 19 March 2024, 14:20 UTC onward. Nothing here is
/// generated — the practice round only plays it back fast.
struct PracticeReplay: Decodable {
    let symbol: String
    let name: String
    let pair: String
    let source: String
    let startUtc: Date
    let intervalSeconds: Int
    @DecimalString var entryPrice: Decimal
    let closes: [String]

    var prices: [Double] { closes.compactMap(Double.init) }
    var entry: Double { NSDecimalNumber(decimal: entryPrice).doubleValue }

    static func load() -> PracticeReplay? {
        guard let url = Bundle.main.url(forResource: "PracticeReplay", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PracticeReplay.self, from: data)
    }

    /// "Mar 19, 2024"
    var dateLabel: String {
        startUtc.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "9 hours" — how much real time the replay covers.
    var durationLabel: String {
        let hours = Double(prices.count * intervalSeconds) / 3600
        return hours >= 1.5 ? "\(Int(hours.rounded())) hours" : "\(Int((hours * 60).rounded())) minutes"
    }
}

/// Onboarding's practice round: $1,000 of practice money in a replay of a real,
/// volatile stretch of WIF history, played back fast. The user decides when to
/// sell — sell during the rally and it's a gain, hold too long and it's a loss.
/// Clearly labeled as a simulated replay; its result never touches the real paper
/// portfolio that the rest of onboarding builds.
struct PracticeRoundStep: View {
    var onContinue: () -> Void

    private enum Phase: Equatable {
        case ready
        case running
        case finished(soldAt: Int, heldToEnd: Bool)
    }

    private static let stake: Double = 1_000
    /// Real 1-minute points played per second — about 30 seconds for the replay.
    private static let pointsPerSecond: Double = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var replay = PracticeReplay.load()
    @State private var phase: Phase = .ready
    @State private var index = 0
    @State private var playback: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack(alignment: .center) {
                        Text("Practice round")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer(minLength: Space.s8)
                        SimulationTag()
                    }
                    Text("Sell whenever you think it's the top.")
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.top, Space.s16)

                if let replay {
                    card(replay)
                } else {
                    EmptyStateView(symbol: "exclamationmark.triangle", title: "Replay unavailable", detail: "Skip ahead to your real trades.")
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s16)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            actionButton
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.s8)
                .background(Color.appBackground)
        }
        .onDisappear { playback?.cancel() }
        .onChange(of: phase) { _, newPhase in
            // Bring the result into view the moment the round ends.
            guard case .finished = newPhase else { return }
            withAnimation(Motion.standard) { proxy.scrollTo("practice.result", anchor: .bottom) }
        }
        }
    }

    // MARK: - Card

    private func card(_ replay: PracticeReplay) -> some View {
        let prices = replay.prices
        let shown = Array(prices.prefix(max(index + 1, 1)))
        let current = shown.last ?? replay.entry
        let value = Self.stake * current / replay.entry
        let pnl = value - Self.stake
        let percent = (current / replay.entry - 1) * 100
        let pnlColor = Color.direction(Decimal(pnl))

        return VStack(alignment: .leading, spacing: Space.s16) {
            HStack(spacing: Metrics.avatarGap) {
                // The coin's real logo, bundled so it shows offline.
                Image("CoinWIF")
                    .resizable()
                    .scaledToFill()
                    .frame(width: Metrics.avatar, height: Metrics.avatar)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(replay.symbol)
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("\(replay.name) · \(replay.dateLabel)")
                        .font(.caption13Digits)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PriceFormat.price(Decimal(current)))
                        .font(.rowValue)
                        .foregroundStyle(Color.textPrimary)
                    Text(timeLabel(replay))
                        .font(.caption13Digits)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            ReplayChart(prices: prices, revealed: shown.count, entry: replay.entry, soldAt: soldIndex)
                .frame(height: 240)

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(phase == .ready ? "Your stake" : "Your position")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                    Text(PriceFormat.usd(Decimal(value)))
                        .heroPriceStyle()
                        .foregroundStyle(Color.textPrimary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: Space.s8)
                Text(phase == .ready
                     ? "Buy at \(PriceFormat.price(replay.entryPrice))"
                     : "\(PriceFormat.signedUSD(Decimal(pnl))) (\(PriceFormat.change(Decimal(percent))))")
                    .font(.rowSubvalue)
                    .foregroundStyle(phase == .ready ? Color.textSecondary : pnlColor)
            }

            Text("\(replay.source) \(replay.pair) · 1-minute prices")
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)

            if case .finished(let soldAt, let heldToEnd) = phase {
                result(replay: replay, soldAt: soldAt, heldToEnd: heldToEnd)
                    .id("practice.result")
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(Space.s20)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                .strokeBorder(Color.appSeparator, lineWidth: 1)
        )
    }

    private var soldIndex: Int? {
        if case .finished(let soldAt, _) = phase { return soldAt }
        return nil
    }

    private func timeLabel(_ replay: PracticeReplay) -> String {
        let date = replay.startUtc.addingTimeInterval(Double(index * replay.intervalSeconds))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d UTC", hour, minute)
    }

    // MARK: - Result

    private func result(replay: PracticeReplay, soldAt: Int, heldToEnd: Bool) -> some View {
        let prices = replay.prices
        let price = prices[min(soldAt, prices.count - 1)]
        let pnl = Self.stake * (price / replay.entry - 1)
        let peak = (prices.max() ?? replay.entry) / replay.entry - 1
        let low = (prices.min() ?? replay.entry) / replay.entry - 1

        let headline = heldToEnd
            ? "Held to the end: \(PriceFormat.signedUSD(Decimal(pnl)))"
            : "You sold for \(PriceFormat.signedUSD(Decimal(pnl)))"

        let message: String
        if pnl >= 0 && price >= (prices.max() ?? price) * 0.97 {
            message = "Nice read — that was close to the top."
        } else if pnl >= 0 {
            message = "Up is up. It peaked at \(PriceFormat.change(Decimal(peak * 100))) — timing is the whole game."
        } else {
            message = "That's why you practice. It was up \(PriceFormat.change(Decimal(peak * 100))) at its high before it turned."
        }

        return VStack(alignment: .leading, spacing: Space.s8) {
            Text(headline)
                .font(.rowTitle)
                .foregroundStyle(Color.direction(Decimal(pnl)))
            Text(message)
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("High \(PriceFormat.change(Decimal(peak * 100))) · Low \(PriceFormat.change(Decimal(low * 100)))")
                .font(.caption13Digits)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .ready:
            Button(replay == nil ? "Skip to real trades" : "Buy $1,000 practice \(replay?.symbol ?? "")") {
                guard replay != nil else { return onContinue() }
                start()
            }
            .buttonStyle(.accent)
            .accessibilityIdentifier("onboarding.practice.buy")
        case .running:
            Button("Sell") { sell(heldToEnd: false) }
                .buttonStyle(.primary)
                .accessibilityIdentifier("onboarding.practice.sell")
        case .finished:
            Button("Now make real trades", action: onContinue)
                .buttonStyle(.accent)
                .accessibilityIdentifier("onboarding.practice.continue")
        }
    }

    private func start() {
        guard let replay else { return }
        Haptics.tap()
        index = 0
        withAnimation(Motion.standard) { phase = .running }
        let total = replay.prices.count
        // Under Reduce Motion the replay still plays (it's the content), just
        // without extra animation on each step.
        let step = max(1, Int((Self.pointsPerSecond / 20).rounded()))
        playback = Task {
            while !Task.isCancelled, index < total - 1 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, phase == .running else { return }
                index = min(total - 1, index + step)
            }
            if phase == .running { sell(heldToEnd: true) }
        }
    }

    private func sell(heldToEnd: Bool) {
        guard phase == .running, let replay else { return }
        playback?.cancel()
        let price = replay.prices[min(index, replay.prices.count - 1)]
        if price >= replay.entry { Haptics.success() } else { Haptics.warning() }
        withAnimation(Motion.standard) {
            phase = .finished(soldAt: index, heldToEnd: heldToEnd)
        }
    }
}

/// "REPLAY · SIMULATED" — the disclosure, as a visible tag at the top of the step.
private struct SimulationTag: View {
    var body: some View {
        HStack(spacing: Space.s4) {
            Image(systemName: "clock.arrow.circlepath")
            Text("REPLAY · SIMULATED")
                .tracking(0.6)
        }
        .font(.caption13.weight(.bold))
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, Space.s12)
        .padding(.vertical, Space.s4 + 2)
        .background(Color.appSurfaceElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.textTertiary, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Replay, simulated. Practice money only.")
    }
}

/// The replay's line, drawn left to right as it plays across a fixed time axis,
/// with a dashed line at the entry price. The y-range follows what's been revealed
/// so far (like a live chart), so the future high and low aren't given away.
private struct ReplayChart: View {
    let prices: [Double]
    let revealed: Int
    let entry: Double
    let soldAt: Int?

    var body: some View {
        let shown = Array(prices.prefix(max(revealed, 2)))
        let low = min(shown.min() ?? entry, entry)
        let high = max(shown.max() ?? entry, entry)
        let pad = max((high - low) * 0.15, entry * 0.01)
        let last = shown.last ?? entry
        let color: Color = last >= entry ? .positive : .negative

        Chart {
            RuleMark(y: .value("Entry", entry))
                .foregroundStyle(Color.textTertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(plotted(shown), id: \.self) { index in
                LineMark(x: .value("Minute", index), y: .value("Price", shown[index]))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            PointMark(x: .value("Minute", shown.count - 1), y: .value("Price", last))
                .foregroundStyle(color)
                .symbolSize(56)

            if let soldAt, prices.indices.contains(soldAt) {
                RuleMark(x: .value("Sold", soldAt))
                    .foregroundStyle(Color.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("Sold")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
            }
        }
        .chartXScale(domain: 0...max(prices.count - 1, 1))
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityLabel("Replay chart")
        .accessibilityValue(last >= entry ? "Above your entry" : "Below your entry")
    }

    /// Every point up to 280, then every other one (always keeping the newest), so a
    /// full replay stays smooth at 20 updates a second.
    private func plotted(_ shown: [Double]) -> [Int] {
        guard shown.count > 280 else { return Array(shown.indices) }
        var indices = Array(stride(from: 0, to: shown.count, by: 2))
        if indices.last != shown.count - 1 { indices.append(shown.count - 1) }
        return indices
    }
}
