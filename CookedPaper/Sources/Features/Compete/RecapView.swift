import SwiftUI

/// Compete → Season → Your monthly recap: one month of the main portfolio, built to be
/// posted. A trader type, the month's return, best and worst trade, the Daily Call
/// record and whether you beat the monkey, plus a 9:16 story card to share.
struct RecapView: View {
    /// UTC months, newest first: this one and the five before it.
    private static let months: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return (0..<6).compactMap { back in
            guard let date = calendar.date(byAdding: .month, value: -back, to: Date()) else { return nil }
            let parts = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", parts.year ?? 2026, parts.month ?? 1)
        }
    }()

    @State private var month = RecapView.months[0]
    @State private var recap: PaperRecap?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s24) {
                ScrollView(.horizontal) {
                    HStack(spacing: Space.s8) {
                        ForEach(Self.months, id: \.self) { candidate in
                            Chip(title: Self.label(candidate), isSelected: candidate == month) {
                                month = candidate
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if isLoading {
                    SkeletonBlock(height: 420, cornerRadius: Radius.card)
                } else if let recap {
                    // Laid out on the real 360×640 canvas, then scaled to the screen, so
                    // the preview is exactly the image that gets shared.
                    GeometryReader { geo in
                        let size = ShareCardStyle.storySize
                        let scale = min(1, geo.size.width / size.width)
                        RecapStoryCard(recap: recap, monthLabel: Self.label(month))
                            .frame(width: size.width, height: size.height)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: size.width * scale, height: size.height * scale)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    }
                    .aspectRatio(ShareCardStyle.storySize.width / ShareCardStyle.storySize.height, contentMode: .fit)

                    ShareImageButton(
                        id: recap.month + recap.personality.id,
                        title: "My \(Self.label(month)) on Cooked",
                        message: "My \(Self.label(month)) trading recap on Cooked. Paper trading. cooked.trade",
                        label: "Share my recap",
                        size: ShareCardStyle.storySize
                    ) { _ in
                        RecapStoryCard(recap: recap, monthLabel: Self.label(month))
                    }
                    .buttonStyle(.accent)
                } else {
                    EmptyStateView(
                        symbol: "sparkles",
                        title: "No recap for this month",
                        detail: errorMessage ?? "Trade during a month to get its recap."
                    )
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s16)
        }
        .screenBackground()
        .reservesTabBarSpace()
        .navigationTitle("Monthly recap")
        .navigationBarTitleDisplayMode(.large)
        .task(id: month) { await load() }
    }

    /// "2026-10" → "October 2026".
    static func label(_ month: String) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return month }
        return "\(Calendar(identifier: .gregorian).monthSymbols[parts[1] - 1]) \(parts[0])"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            recap = try await LeaderboardAPI.recap(month: month)
        } catch {
            recap = nil
            errorMessage = error.isNotFound ? nil : error.localizedDescription
        }
        isLoading = false
    }
}

/// The recap as a 9:16 poster, drawn on the share-card canvas so the in-app preview
/// and the shared image are the same picture.
struct RecapStoryCard: View {
    let recap: PaperRecap
    let monthLabel: String

    private var returnPct: Decimal? {
        recap.returnPct.unavailable == nil ? recap.returnPct.pct : nil
    }

    var body: some View {
        ZStack {
            ShareCardStyle.background
            VStack(alignment: .leading, spacing: 18) {
                Text(monthLabel.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.6))

                VStack(alignment: .leading, spacing: 6) {
                    Text("I'm")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text(recap.personality.title)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recap.personality.description)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(ShareCardFormat.pnl(returnPct))
                    .font(.system(size: 54, weight: .heavy).monospacedDigit())
                    .foregroundStyle(returnPct.map { $0 < 0 ? Color.negative : Color.positive } ?? .white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                VStack(spacing: 10) {
                    statRow("Trades", "\(recap.tradeCount)")
                    statRow("Win rate", recap.winRatePct.pct.map { PriceFormat.percentPlain($0) } ?? "—")
                    if let best = recap.bestTrade {
                        statRow("Best trade", "\(best.symbol ?? "?") \(ShareCardFormat.pnl(best.returnPct))")
                    }
                    if let worst = recap.worstTrade {
                        statRow("Worst trade", "\(worst.symbol ?? "?") \(ShareCardFormat.pnl(worst.returnPct))")
                    }
                    if recap.dailyCall.played > 0 {
                        statRow("Daily Call", "\(recap.dailyCall.correct) of \(recap.dailyCall.played)")
                    }
                }

                if let monkey = recap.monkey, let beat = monkey.beatMonkey {
                    Text(beat ? "🐒 Beat the monkey (\(ShareCardFormat.pnl(monkey.returnPct)))"
                              : "🐒 The monkey won (\(ShareCardFormat.pnl(monkey.returnPct)))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(beat ? Color.positive : Color.negative)
                }

                Spacer(minLength: 0)

                HStack {
                    BrandWordmark(height: 20)
                    Spacer()
                    Text(ShareCardStyle.footer)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(28)
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.65))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}
