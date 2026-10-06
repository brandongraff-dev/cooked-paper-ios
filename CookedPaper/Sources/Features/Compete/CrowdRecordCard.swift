import SwiftUI

/// "The crowd": how often the Daily Call's majority has called it right lately, and
/// how betting against them would have gone. Under the Daily Call on Compete, with
/// a share button, because a public record of what traders think is the number
/// people screenshot.
///
/// Hides itself while the record is too thin to mean anything (fewer than
/// `minimumDays` counted days), and when the server doesn't have it yet (404).
struct CrowdRecordCard: View {
    static let minimumDays = 5

    @State private var record: DailyCallCrowdRecord?

    var body: some View {
        VStack(spacing: 0) {
            if let record, record.sampleSize >= Self.minimumDays {
                CrowdRecordContent(record: record)
            }
        }
        .task { await load() }
    }

    private func load() async {
        // Any failure leaves the card hidden; it's a nice-to-have, not a screen.
        record = try? await DailyCallAPI.crowdRecord()
    }
}

struct CrowdRecordContent: View {
    let record: DailyCallCrowdRecord

    /// Oldest to newest, left to right, at most two weeks.
    private var recentDays: [DailyCallCrowdDay] {
        Array(record.days.prefix(14).reversed())
    }

    private var runLine: String? {
        let days = abs(record.currentRun)
        guard days >= 2 else { return nil }
        return record.currentRun > 0
            ? "Right \(days) days running"
            : "Wrong \(days) days running"
    }

    private var shareText: String {
        "The Cooked crowd has called the Daily Call right \(record.crowdRight) of the last \(record.sampleSize) days. "
            + "Betting against them: \(record.crowdWrong)–\(record.crowdRight). Paper game, no stakes."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack {
                Text("The crowd")
                    .font(.sectionHeader)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .accessibilityLabel("Share the crowd record")
            }

            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Right \(record.crowdRight) of the last \(record.sampleSize) days")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                if let runLine {
                    Text(runLine)
                        .font(.rowSubtitle)
                        .foregroundStyle(record.currentRun > 0 ? Color.positive : Color.negative)
                }
            }

            dayStrip

            Text("Fading the crowd: \(record.crowdWrong)–\(record.crowdRight)")
                .font(.rowSubvalue)
                .foregroundStyle(Color.textSecondary)

            Text(record.disclaimer ?? "Paper game: simulated prices, no stakes, no prizes.")
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(Space.s20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// One mark per day: a check where the crowd was right, a cross where it was
    /// wrong. The symbol carries the meaning, not just the colour.
    private var dayStrip: some View {
        HStack(spacing: Space.s4) {
            ForEach(recentDays) { day in
                Image(systemName: day.crowdRight ? "checkmark" : "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(day.crowdRight ? Color.positive : Color.negative)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(
                        (day.crowdRight ? Color.positive : Color.negative).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: Radius.small / 2, style: .continuous)
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Last \(recentDays.count) days, oldest first: "
                + recentDays.map { $0.crowdRight ? "right" : "wrong" }.joined(separator: ", ")
        )
    }
}
