import SwiftUI

/// Beat the Monkey, above the leaderboard: "The Monkey" is a house bot that trades at
/// random, and this says how many ranked traders are doing better than it, and
/// whether you are. Built to be screenshotted, so it has a share button.
///
/// Hidden until the monkey ranks in the selected window, and when the server doesn't
/// have the standing yet (any error).
struct BeatTheMonkeyCard: View {
    let window: LeaderboardWindow
    /// Your row on the board in this window, when you're ranked.
    let myEntry: PaperLeaderboardEntry?

    @State private var standing: PaperMonkeyStanding?

    var body: some View {
        VStack(spacing: 0) {
            if let standing, let monkey = standing.monkey, let beating = standing.beatingMonkey {
                content(standing: standing, monkey: monkey, beating: beating)
            }
        }
        .task(id: window) {
            standing = try? await LeaderboardAPI.monkeyStanding(window: window)
        }
    }

    private func content(standing: PaperMonkeyStanding, monkey: PaperLeaderboardEntry, beating: Int) -> some View {
        let monkeyPct = monkey.returnPct.unavailable == nil ? monkey.returnPct.pct : nil
        let headline = "\(beating) of \(standing.sampleSize) traders are beating the monkey"
        return VStack(alignment: .leading, spacing: Space.s12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Beat the Monkey 🐒")
                    .font(.sectionHeader)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                ShareLink(item: shareText(headline: headline)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .accessibilityLabel("Share Beat the Monkey")
            }

            Text(headline)
                .font(.rowTitle)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.s8) {
                Text("The monkey trades at random:")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                ChangeText(percent: monkeyPct, font: .rowValue)
            }

            if let verdict = verdict(monkeyPct: monkeyPct) {
                Text(verdict.text)
                    .font(.rowSubtitle.weight(.semibold))
                    .foregroundStyle(verdict.isBeating ? Color.positive : Color.negative)
            }

            Text("Paper trading, simulated. Ranked by the same rules as everyone.")
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(Space.s20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// Your return against the monkey's, when you're ranked. A tie goes to the monkey,
    /// as it does on the server.
    private func verdict(monkeyPct: Decimal?) -> (text: String, isBeating: Bool)? {
        guard let myEntry, !myEntry.isHouseBot,
              myEntry.returnPct.unavailable == nil,
              let mine = myEntry.returnPct.pct, let monkeyPct
        else { return nil }
        return mine > monkeyPct
            ? ("You're beating the monkey.", true)
            : ("The monkey is beating you.", false)
    }

    private func shareText(headline: String) -> String {
        "\(headline) on Cooked. A bot that trades at random. Are you beating it? (Paper trading, no real money.)"
    }
}
