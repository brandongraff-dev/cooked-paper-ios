import SwiftUI

/// Compete → Crash Replay: real historical crashes, played blind. The first scenario is
/// free; the rest are Pro.
struct ReplayListView: View {
    @State private var response: ReplayListResponse?
    @State private var errorMessage: String?
    @State private var playing: ReplaySummary?
    @State private var showsPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    Text("Survive the crash")
                        .font(.appLargeTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Real crashes from crypto history, hour by hour, with the name and date hidden. You get $10,000. Find out what it was when it's over.")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let response {
                    VStack(spacing: Space.s12) {
                        ForEach(response.scenarios) { scenario in
                            Button {
                                if scenario.number > 1 && !FreeTier.shared.isPro {
                                    showsPaywall = true
                                } else {
                                    playing = scenario
                                }
                            } label: {
                                row(scenario)
                            }
                            .buttonStyle(.pressable)
                            .accessibilityIdentifier("replay.\(scenario.number)")
                        }
                    }
                } else if let errorMessage {
                    EmptyStateView(symbol: "chart.line.downtrend.xyaxis", title: "Couldn't load replays", detail: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    SkeletonBlock(height: 280, cornerRadius: Radius.card)
                }
                Text("Paper game on real historical prices. No fees, no stakes.")
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s16)
        }
        .screenBackground()
        .reservesTabBarSpace()
        .navigationTitle("Crash Replay")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .fullScreenCover(item: $playing, onDismiss: { Task { await load() } }) { scenario in
            ReplayPlayerView(summary: scenario)
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(reason: .locked("Every crash replay")) { showsPaywall = false }
        }
    }

    private func row(_ scenario: ReplaySummary) -> some View {
        HStack(spacing: Space.s12) {
            Image(systemName: scenario.number > 1 && !FreeTier.shared.isPro ? "lock.fill" : "play.fill")
                .foregroundStyle(Color.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mystery crash #\(scenario.number)")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("\(scenario.difficulty.capitalized) · \(scenario.candleCount) hours · \(scenario.players) played")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if let best = scenario.bestReturnPct {
                VStack(alignment: .trailing, spacing: 2) {
                    ChangeText(percent: best, font: .rowValue)
                    Text("your best")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(Space.s16)
        .glassCard()
    }

    private func load() async {
        do {
            response = try await ReplayAPI.list()
            errorMessage = nil
        } catch {
            if response == nil { errorMessage = error.localizedDescription }
        }
    }
}

/// The game: candles play forward one hour at a time. Buy with part of your cash or sell
/// part of your holding at the latest close. When the last candle prints, the run goes to
/// the server to be scored, and the crash is revealed.
struct ReplayPlayerView: View {
    let summary: ReplaySummary

    @Environment(\.dismiss) private var dismiss
    @State private var scenario: ReplayScenario?
    @State private var index = 0
    @State private var isPlaying = false
    @State private var cash: Double = 10_000
    @State private var units: Double = 0
    @State private var actions: [ReplayAction] = []
    @State private var result: ReplayResult?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var speed: Double = 1

    private var candles: [[Double]] { scenario?.candles ?? [] }
    private var price: Double { candles.indices.contains(index) ? candles[index][3] : 0 }
    private var equity: Double { cash + units * price }
    private var returnPct: Double { (equity - 10_000) / 10_000 * 100 }
    private var isOver: Bool { !candles.isEmpty && index >= candles.count - 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.s16) {
                if let result, let scenario {
                    ReplayResultView(scenario: scenario, actions: actions, result: result) { dismiss() }
                } else if scenario != nil {
                    stats
                    CrashReplayChart(candles: Array(candles.prefix(index + 1)), actions: actions)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Price chart, hour \(index + 1) of \(candles.count)")
                    controls
                } else if let errorMessage {
                    EmptyStateView(symbol: "wifi.slash", title: "Couldn't load this replay", detail: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(Space.margin)
            .screenBackground()
            .navigationTitle("Mystery crash #\(summary.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Quit") { dismiss() }
                }
            }
        }
        .task { await load() }
        .task(id: isPlaying) { await play() }
    }

    private var stats: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hour \(index + 1) of \(candles.count)")
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                Text(String(format: "$%.2f", equity))
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(units > 0 ? "In: \(Int((units * price / max(equity, 1) * 100).rounded()))%" : "All cash")
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                ChangeText(percent: Decimal(returnPct), font: .rowValue)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: Space.s12) {
            HStack(spacing: Space.s8) {
                tradeButton("Buy 50%", side: "buy", fraction: 0.5, enabled: cash > 1)
                tradeButton("Buy all", side: "buy", fraction: 1, enabled: cash > 1)
                tradeButton("Sell 50%", side: "sell", fraction: 0.5, enabled: units > 0)
                tradeButton("Sell all", side: "sell", fraction: 1, enabled: units > 0)
            }
            HStack(spacing: Space.s8) {
                Button(isPlaying ? "Pause" : (index == 0 ? "Start" : "Play")) {
                    isPlaying.toggle()
                }
                .buttonStyle(.accent)
                .disabled(isOver)
                .accessibilityIdentifier("replay.play")
                Button(speed == 1 ? "1×" : "3×") { speed = speed == 1 ? 3 : 1 }
                    .buttonStyle(.secondary)
                    .frame(width: 72)
            }
            if isSubmitting { ProgressView("Scoring your run…") }
        }
    }

    private func tradeButton(_ title: String, side: String, fraction: Double, enabled: Bool) -> some View {
        Button(title) { trade(side: side, fraction: fraction) }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.secondary)
            .disabled(!enabled || isOver || isSubmitting)
    }

    private func trade(side: String, fraction: Double) {
        guard price > 0 else { return }
        Haptics.tap()
        if side == "buy" {
            let spend = cash * fraction
            units += spend / price
            cash -= spend
        } else {
            let sold = units * fraction
            cash += sold * price
            units -= sold
        }
        actions.append(ReplayAction(candle: index, side: side, fraction: fraction))
    }

    private func load() async {
        do {
            scenario = try await ReplayAPI.get(id: summary.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// One candle every 0.6 s (0.2 s at 3×) while playing; submits at the end.
    private func play() async {
        while isPlaying && !isOver {
            try? await Task.sleep(for: .milliseconds(Int(600 / speed)))
            guard isPlaying, !Task.isCancelled else { return }
            index += 1
        }
        if isOver && result == nil && !isSubmitting {
            isPlaying = false
            await submit()
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            result = try await ReplayAPI.submit(id: summary.id, actions: actions)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Candles drawn up to the current hour, scaled to what is on screen, with a dot where
/// each move was made (green buy, red sell).
struct CrashReplayChart: View {
    let candles: [[Double]]
    let actions: [ReplayAction]
    var positive: Color = .positive
    var negative: Color = .negative

    var body: some View {
        Canvas { context, size in
            guard !candles.isEmpty else { return }
            let highs = candles.map { $0[1] }
            let lows = candles.map { $0[2] }
            let top = highs.max() ?? 1
            let bottom = lows.min() ?? 0
            let span = max(top - bottom, 0.000_001)
            let slots = max(candles.count, 24)
            let slot = size.width / CGFloat(slots)
            func y(_ value: Double) -> CGFloat {
                size.height * CGFloat(1 - (value - bottom) / span)
            }
            for (i, c) in candles.enumerated() {
                let x = slot * (CGFloat(i) + 0.5)
                let up = c[3] >= c[0]
                let color = up ? positive : negative
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: y(c[1])))
                wick.addLine(to: CGPoint(x: x, y: y(c[2])))
                context.stroke(wick, with: .color(color), lineWidth: 1)
                let bodyTop = y(max(c[0], c[3]))
                let bodyHeight = max(1, abs(y(c[0]) - y(c[3])))
                context.fill(
                    Path(CGRect(x: x - slot * 0.35, y: bodyTop, width: slot * 0.7, height: bodyHeight)),
                    with: .color(color)
                )
            }
            for action in actions where action.candle < candles.count {
                let x = slot * (CGFloat(action.candle) + 0.5)
                let point = CGPoint(x: x, y: y(candles[action.candle][3]))
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                    with: .color(action.side == "buy" ? positive : negative)
                )
                context.stroke(
                    Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                    with: .color(.white),
                    lineWidth: 1.5
                )
            }
        }
    }
}

/// The reveal: SURVIVED or COOKED, your return against buy-and-hold, what the crash
/// was, your rank, and the clip to post.
struct ReplayResultView: View {
    let scenario: ReplayScenario
    let actions: [ReplayAction]
    let result: ReplayResult
    let onDone: () -> Void

    @State private var clipURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var stamped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s20) {
                // The verdict lands like a stamp: big, tilted, then settles.
                Text(result.survived ? "SURVIVED" : "COOKED")
                    .font(.system(size: 46, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s24)
                    .padding(.vertical, Space.s8)
                    .background(
                        LinearGradient.tile(result.survived ? Color.positive : Color.negative),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    )
                    .shadow(color: (result.survived ? Color.positive : Color.negative).opacity(0.5), radius: 24, y: 8)
                    .rotationEffect(.degrees(-6))
                    .scaleEffect(stamped || reduceMotion ? 1 : 1.8)
                    .opacity(stamped || reduceMotion ? 1 : 0)
                    .padding(.top, Space.s16)
                    .accessibilityIdentifier("replay.verdict")
                    .onAppear {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { stamped = true }
                        if result.survived { Haptics.success() }
                    }
                HStack(spacing: Space.s24) {
                    VStack(spacing: 2) {
                        ChangeText(percent: result.returnPct, font: .system(size: 28, weight: .bold).monospacedDigit())
                        Text("you").font(.caption13).foregroundStyle(Color.textSecondary)
                    }
                    VStack(spacing: 2) {
                        ChangeText(percent: result.holdReturnPct, font: .system(size: 28, weight: .bold).monospacedDigit())
                        Text("buy & hold").font(.caption13).foregroundStyle(Color.textSecondary)
                    }
                }
                Text("#\(result.rank) of \(result.sampleSize) players")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)

                VStack(alignment: .leading, spacing: Space.s8) {
                    Text("It was \(result.reveal.name)")
                        .font(.sectionHeader)
                        .foregroundStyle(Color.textPrimary)
                    Text(result.reveal.date)
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                    Text(result.reveal.story)
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                if let clipURL {
                    ShareLink(item: clipURL) {
                        Label("Share your clip", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.accent)
                } else {
                    Button {
                        Task { await export() }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Label("Make a 15-second clip", systemImage: "film")
                        }
                    }
                    .buttonStyle(.accent)
                    .disabled(isExporting)
                    .accessibilityIdentifier("replay.export")
                }
                if let exportError {
                    Text(exportError)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                }
                ProUpsellCard(
                    symbol: "chart.line.downtrend.xyaxis",
                    color: .tileTeal,
                    title: result.survived ? "Try a harder crash" : "Run it back",
                    detail: "FTX and LUNA are waiting. Every crash replay comes with Pro.",
                    reason: .locked("Every crash replay")
                )
                Button("Done", action: onDone)
                    .buttonStyle(.secondary)
            }
            .padding(.vertical, Space.s16)
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            clipURL = try await ReplayClipExporter.export(
                candles: scenario.candles,
                actions: actions,
                result: result,
                number: scenario.number
            )
        } catch {
            exportError = "Couldn't make the clip. Try again."
        }
    }
}
