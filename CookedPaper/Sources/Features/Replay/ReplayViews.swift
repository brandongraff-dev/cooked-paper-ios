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
                header
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
                            .accessibilityLabel("Mystery crash \(scenario.number), \(scenario.difficulty), \(scenario.players) played\(scenario.number > 1 && !FreeTier.shared.isPro ? ", Pro" : "")")
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

    /// "1 of 4 played · best +4.12%" over the rules as pills, like the challenge ladder.
    private var header: some View {
        let scenarios = response?.scenarios ?? []
        let played = scenarios.filter { $0.bestReturnPct != nil }
        let best = played.compactMap(\.bestReturnPct).max()
        return VStack(alignment: .leading, spacing: Space.s12) {
            if !scenarios.isEmpty {
                HStack(spacing: Space.s8) {
                    Text("\(played.count) of \(scenarios.count) played")
                        .foregroundStyle(Color.textPrimary)
                    if let best {
                        Text("·").foregroundStyle(Color.textTertiary)
                        Text("best").foregroundStyle(Color.textSecondary)
                        ChangeText(percent: best, font: .rowTitle)
                    }
                }
                .font(.rowTitle)
            }
            InfoPillRow(pills: [
                (symbol: "dollarsign.circle.fill", text: "$10K start"),
                (symbol: "eye.slash.fill", text: "Names hidden"),
            ])
            // Nothing played yet: the free first crash, one tap away.
            if played.isEmpty, let first = scenarios.first(where: { $0.number == 1 }) ?? scenarios.first {
                Button {
                    Haptics.tap()
                    playing = first
                } label: {
                    Label("Play Crash #\(first.number)", systemImage: "play.fill")
                }
                .buttonStyle(.accent)
                .padding(.top, Space.s8)
                .accessibilityIdentifier("replay.firstPlay")
            }
        }
    }

    private func row(_ scenario: ReplaySummary) -> some View {
        let locked = scenario.number > 1 && !FreeTier.shared.isPro
        return VStack(alignment: .leading, spacing: Space.s12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.difficulty.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.textSecondary)
                    Text("Crash #\(scenario.number)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(locked ? Color.textTertiary : Color.textPrimary)
                }
                Spacer()
                DifficultyFlames(difficulty: scenario.difficulty)
            }
            TeaserChart(values: scenario.teaser ?? [])
                .frame(height: 80)
            HStack(alignment: .center, spacing: Space.s12) {
                Label("\(scenario.players)", systemImage: "person.2.fill")
                    .font(.caption13Digits)
                    .foregroundStyle(Color.textSecondary)
                    .labelStyle(.titleAndIcon)
                Spacer()
                if let best = scenario.bestReturnPct {
                    ChangePill(percent: best)
                } else if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 28, height: 28)
                        .metalSurface(Circle())
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentInk)
                        .frame(width: 28, height: 28)
                        .background(Color.accent, in: Circle())
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

/// How a crash starts, then a question mark where it goes: the first third of the run
/// as a line over a flat fill, then a dashed line into the unknown.
struct TeaserChart: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let low = values.min(), let high = values.max() else { return }
            let known = size.width * 0.62
            let span = max(high - low, 0.0001)
            func point(_ i: Int) -> CGPoint {
                CGPoint(
                    x: known * CGFloat(i) / CGFloat(values.count - 1),
                    y: size.height * 0.12 + (1 - CGFloat((values[i] - low) / span)) * size.height * 0.6
                )
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }

            var area = line
            area.addLine(to: CGPoint(x: known, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(Color.white.opacity(0.05)))
            context.stroke(
                line,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
            // Where the story continues: a dashed line off into the unknown.
            let end = point(values.count - 1)
            var unknown = Path()
            unknown.move(to: end)
            unknown.addLine(to: CGPoint(x: size.width * 0.8, y: end.y))
            context.stroke(
                unknown,
                with: .color(.white.opacity(0.35)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5])
            )
            let dot = CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dot.insetBy(dx: -5, dy: -5)), with: .color(.white.opacity(0.18)))
            context.fill(Path(ellipseIn: dot), with: .color(.white))
        }
        .overlay(alignment: .trailing) {
            Text("?")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textTertiary)
                .padding(.trailing, Space.s8)
        }
        .accessibilityHidden(true)
    }
}

/// Difficulty as flames: one for medium, two for hard, three for brutal.
struct DifficultyFlames: View {
    let difficulty: String

    private var count: Int {
        switch difficulty {
        case "brutal": 3
        case "hard": 2
        default: 1
        }
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "flame.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        index < count ? Color.tileOrange : Color.white.opacity(0.15)
                    )
            }
        }
        .accessibilityLabel(difficulty)
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

/// The reveal. A headline verdict, then the whole crash drawn at last: the price (what
/// buy-and-hold got) against your account, both from the same start, with every buy
/// and sell on it. Then the numbers, what the crash was, and the clip to post.
struct ReplayResultView: View {
    let scenario: ReplayScenario
    let actions: [ReplayAction]
    let result: ReplayResult
    let onDone: () -> Void

    @State private var clipURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var verdictColor: Color { result.survived ? .positive : .negative }
    private var curves: ReplayCurves { ReplayCurves(candles: scenario.candles, actions: actions) }
    private var edge: Decimal { result.returnPct - result.holdReturnPct }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s20) {
                header
                chartCard
                statTiles
                revealCard
                actionsBlock
            }
            .padding(.vertical, Space.s8)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            let still = reduceMotion || ProcessInfo.processInfo.environment["UITEST_STILL_FRAMES"] == "1"
            if still { drawn = 1 } else { withAnimation(.easeInOut(duration: 1.4)) { drawn = 1 } }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            HStack(spacing: 6) {
                Image(systemName: result.survived ? "checkmark.seal.fill" : "flame.fill")
                Text(result.survived ? "SURVIVED" : "COOKED")
                    .tracking(1.4)
            }
            .font(.caption.weight(.heavy))
            .foregroundStyle(verdictColor)
            .padding(.horizontal, Space.s12)
            .padding(.vertical, 6)
            .background(verdictColor.opacity(0.15), in: Capsule())
            .accessibilityIdentifier("replay.verdict")

            Text(result.survived ? "You made it out" : "You got cooked")
                .font(.system(size: 36, weight: .heavy))
                .tracking(-1)
                .foregroundStyle(Color.textPrimary)
            Text("#\(result.rank) of \(result.sampleSize) players on this crash")
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            ReplayRevealChart(curves: curves, drawn: drawn)
                .frame(height: 190)
                .padding(.top, Space.s20)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: Space.s8) {
                        HStack(spacing: 4) { dot(.positive); Text("Buy") }
                        HStack(spacing: 4) { dot(.negative); Text("Sell") }
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                }
                .accessibilityLabel("Your account against buy and hold over the whole crash")
            HStack(spacing: Space.s20) {
                legend(Color.accent, "You", result.returnPct)
                legend(Color.white.opacity(0.55), "Buy & hold", result.holdReturnPct)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
        }
        .padding(Space.s16)
        .glassCard()
    }

    private func legend(_ color: Color, _ label: String, _ pct: Decimal) -> some View {
        HStack(spacing: Space.s8) {
            Capsule().fill(color).frame(width: 14, height: 3)
            Text(label).font(.caption13).foregroundStyle(Color.textSecondary)
            ChangeText(percent: pct, font: .caption13Digits.weight(.semibold))
        }
        .fixedSize()
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }

    private var statTiles: some View {
        HStack(spacing: Space.s8) {
            tile("You", PriceFormat.change(result.returnPct), Color.direction(result.returnPct))
            tile("vs hold", PriceFormat.change(edge), Color.direction(edge))
            tile("Trades", "\(actions.count)", Color.textPrimary)
        }
    }

    private func tile(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s12)
        .glassCard(cornerRadius: Radius.small)
        .accessibilityElement(children: .combine)
    }

    private var revealCard: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("IT WAS")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                Text(result.reveal.name)
                    .font(.sectionHeader)
                    .foregroundStyle(Color.textPrimary)
                Text(result.reveal.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .metalSurface(Capsule())
            }
            Text(result.reveal.date)
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
            Text(result.reveal.story)
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var actionsBlock: some View {
        VStack(spacing: Space.s12) {
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

/// The run replayed from the candles and your moves: the price and your account, each
/// as a percentage from the first close, hour by hour. The same arithmetic the player
/// uses (a move fills at that hour's close), so the end points match the score.
struct ReplayCurves {
    let price: [Double]
    let you: [Double]
    /// (hour, side) for every move, to mark on the price line.
    let moves: [(Int, String)]

    init(candles: [[Double]], actions: [ReplayAction]) {
        let closes = candles.map { $0[3] }
        guard let first = closes.first, first > 0 else {
            price = []; you = []; moves = []; return
        }
        let byHour = Dictionary(grouping: actions, by: \.candle)
        var cash = 10_000.0, units = 0.0
        var priceCurve: [Double] = [], youCurve: [Double] = []
        for (hour, close) in closes.enumerated() {
            for action in byHour[hour] ?? [] {
                if action.side == "buy" {
                    let spend = cash * action.fraction
                    units += spend / close
                    cash -= spend
                } else {
                    let sold = units * action.fraction
                    cash += sold * close
                    units -= sold
                }
            }
            priceCurve.append((close / first - 1) * 100)
            youCurve.append(((cash + units * close) / 10_000 - 1) * 100)
        }
        price = priceCurve
        you = youCurve
        moves = actions.map { ($0.candle, $0.side) }
    }
}

/// Both curves over a zero line, drawn in from the left as `drawn` goes 0 → 1, with a
/// dot at each move and at each line's end.
struct ReplayRevealChart: View {
    let curves: ReplayCurves
    var drawn: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let all = curves.price + curves.you + [0]
            let top = (all.max() ?? 1) + 2
            let bottom = (all.min() ?? -1) - 2
            let span = max(top - bottom, 0.0001)
            let count = max(curves.price.count - 1, 1)
            let point = { (i: Int, v: Double) in
                CGPoint(x: size.width * CGFloat(i) / CGFloat(count),
                        y: size.height * CGFloat((top - v) / span))
            }
            ZStack {
                // Zero: where both started.
                Path { p in
                    let y = point(0, 0).y
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                CurveShape(values: curves.price, top: top, span: span)
                    .trim(from: 0, to: drawn)
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                CurveShape(values: curves.you, top: top, span: span)
                    .trim(from: 0, to: drawn)
                    .stroke(Color.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                ForEach(Array(curves.moves.enumerated()), id: \.offset) { _, move in
                    if curves.price.indices.contains(move.0) {
                        Circle()
                            .fill(move.1 == "buy" ? Color.positive : Color.negative)
                            .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 1.5))
                            .frame(width: 10, height: 10)
                            .position(point(move.0, curves.price[move.0]))
                            .opacity(CGFloat(move.0) / CGFloat(count) <= drawn ? 1 : 0)
                    }
                }
                if let last = curves.you.last, drawn >= 1 {
                    Circle().fill(Color.accent).frame(width: 9, height: 9)
                        .position(point(curves.you.count - 1, last))
                }
                if let last = curves.price.last, drawn >= 1 {
                    Circle().fill(Color.white.opacity(0.7)).frame(width: 7, height: 7)
                        .position(point(curves.price.count - 1, last))
                }
            }
        }
    }

    private struct CurveShape: Shape {
        let values: [Double]
        let top: Double
        let span: Double

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let count = max(values.count - 1, 1)
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: rect.width * CGFloat(i) / CGFloat(count),
                                y: rect.height * CGFloat((top - v) / span))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            return path
        }
    }
}
