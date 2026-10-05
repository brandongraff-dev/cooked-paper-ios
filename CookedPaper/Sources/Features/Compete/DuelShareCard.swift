import Foundation
import SwiftUI

/// What a duel result card shows: both players, both returns, the verdict, and
/// the invite link when the duel still has one.
struct DuelShareCardModel: Hashable {
    let myUsername: String
    let mySeed: String
    let myReturnPct: Decimal?
    let theirUsername: String
    let theirSeed: String
    let theirReturnPct: Decimal?
    let outcome: DuelOutcome
    let durationLabel: String
    /// "cooked.trade/d/<code>", nil without an invite code. Drawn on the card.
    let link: String?
    /// "https://cooked.trade/d/<code>", nil without an invite code. Shared in the
    /// message.
    let shareURL: String?

    /// Nil until the duel has a result and an opponent.
    init?(duel: Duel) {
        guard let outcome = duel.outcome, let me = duel.me, let them = duel.them else { return nil }
        self.init(
            myUsername: me.username,
            mySeed: me.seed,
            myReturnPct: me.returnPct,
            theirUsername: them.username,
            theirSeed: them.seed,
            theirReturnPct: them.returnPct,
            outcome: outcome,
            durationLabel: duel.durationLabel,
            inviteCode: duel.inviteCode
        )
    }

    init(
        myUsername: String,
        mySeed: String,
        myReturnPct: Decimal?,
        theirUsername: String,
        theirSeed: String,
        theirReturnPct: Decimal?,
        outcome: DuelOutcome,
        durationLabel: String,
        inviteCode: String?
    ) {
        self.myUsername = myUsername
        self.mySeed = mySeed
        self.myReturnPct = myReturnPct
        self.theirUsername = theirUsername
        self.theirSeed = theirSeed
        self.theirReturnPct = theirReturnPct
        self.outcome = outcome
        self.durationLabel = durationLabel
        link = ShareCardFormat.duelLink(code: inviteCode)
        shareURL = ShareCardFormat.duelURL(code: inviteCode)
    }

    var shareTitle: String { "@\(myUsername) vs @\(theirUsername) on Cooked" }

    var shareMessage: String {
        let line: String
        switch outcome {
        case .won: line = "Won my paper duel vs @\(theirUsername)"
        case .lost: line = "Lost my paper duel vs @\(theirUsername)"
        case .draw: line = "Drew my paper duel vs @\(theirUsername)"
        }
        let link = shareURL.map { " Duel me: \($0)" } ?? " cooked.trade"
        return "\(line): \(ShareCardFormat.pnl(myReturnPct)) to \(ShareCardFormat.pnl(theirReturnPct)). Paper money, no stakes.\(link)"
    }
}

/// The duel result card: WIN/LOSS/DRAW, you vs them with both returns.
struct DuelShareCard: View {
    let model: DuelShareCardModel

    private var verdictColor: Color {
        switch model.outcome {
        case .won: .positive
        case .lost: .negative
        case .draw: .textPrimary
        }
    }

    var body: some View {
        ShareCardCanvas(tag: "PAPER DUEL") {
            VStack(alignment: .leading, spacing: Space.s24) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(ShareCardFormat.verdict(model.outcome))
                        .font(.system(size: 72, weight: .heavy))
                        .tracking(-1)
                        .foregroundStyle(verdictColor)
                        .lineLimit(1)
                    Text("\(model.durationLabel) paper duel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }

                HStack(alignment: .top, spacing: Space.s12) {
                    player(
                        username: model.myUsername,
                        seed: model.mySeed,
                        returnPct: model.myReturnPct,
                        isWinner: model.outcome == .won,
                        alignment: .leading
                    )
                    Text("vs")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, 18)
                    player(
                        username: model.theirUsername,
                        seed: model.theirSeed,
                        returnPct: model.theirReturnPct,
                        isWinner: model.outcome == .lost,
                        alignment: .trailing
                    )
                }
                .padding(Space.s16)
                .background(
                    Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                )

                if let link = model.link {
                    HStack(spacing: Space.s8) {
                        Image(systemName: "link")
                            .font(.system(size: 13, weight: .semibold))
                        Text(link)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(ShareCardStyle.glow)
                }
            }
        }
    }

    private func player(username: String, seed: String, returnPct: Decimal?, isWinner: Bool, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Space.s8) {
            ProfileAvatar(seed: seed, name: username, size: 48)
                .overlay(alignment: .topTrailing) {
                    if isWinner {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AchievementTier.gold.color)
                            .padding(4)
                            .background(ShareCardStyle.background, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
            Text("@\(username)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(ShareCardFormat.pnl(returnPct))
                .font(.system(size: 26, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.direction(returnPct))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

/// The share button for a finished duel; shows nothing until the duel has a result.
struct DuelShareButton: View {
    let duel: Duel

    var body: some View {
        if let model = DuelShareCardModel(duel: duel) {
            ShareImageButton(
                id: model,
                title: model.shareTitle,
                message: model.shareMessage,
                label: "Share result"
            ) { _ in
                DuelShareCard(model: model)
            }
        }
    }
}

#if DEBUG
#Preview("Duel card · win with link") {
    DuelShareCard(
        model: DuelShareCardModel(
            myUsername: "degenchef",
            mySeed: "u1",
            myReturnPct: Decimal(string: "38.42"),
            theirUsername: "papahands",
            theirSeed: "u2",
            theirReturnPct: Decimal(string: "-12.07"),
            outcome: .won,
            durationLabel: "24h",
            inviteCode: "K7QX2M"
        )
    )
}

#Preview("Duel card · loss") {
    DuelShareCard(
        model: DuelShareCardModel(
            myUsername: "degenchef",
            mySeed: "u1",
            myReturnPct: Decimal(string: "-4.10"),
            theirUsername: "papahands",
            theirSeed: "u2",
            theirReturnPct: Decimal(string: "112.5"),
            outcome: .lost,
            durationLabel: "7d",
            inviteCode: nil
        )
    )
}
#endif
