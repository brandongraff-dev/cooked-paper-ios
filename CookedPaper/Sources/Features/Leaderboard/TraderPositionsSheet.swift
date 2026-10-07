import SwiftUI

/// What a ranked trader holds right now, opened from a leaderboard row. Shares of
/// their portfolio and unrealized returns only, never amounts.
///
/// Pro sees the positions. Free sees them blurred under "See what #N is holding",
/// which opens the paywall: the last of the free tier's upgrade moments.
struct TraderPositionsSheet: View {
    let entry: PaperLeaderboardEntry

    @Environment(\.dismiss) private var dismiss
    @State private var positions: PaperTraderPositions?
    @State private var isLoading = true
    @State private var isUnavailable = false
    @State private var showsPaywall = false

    private var isPro: Bool { FreeTier.shared.isPro }
    private var title: String { entry.isHouseBot ? "The Monkey" : "@\(entry.username)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s24) {
                    header
                    content
                    Text("Paper trading, simulated. Shares of the portfolio, not amounts.")
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.s16)
            }
            .background(Color.appSurfaceElevated)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(reason: .locked("Top traders' positions")) { showsPaywall = false }
        }
    }

    private var header: some View {
        HStack(spacing: Space.s12) {
            MonogramAvatar(text: entry.username)
            VStack(alignment: .leading, spacing: 2) {
                Text("#\(entry.rank) this month")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("\(entry.roundTripCount) round trips")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            ChangeText(
                percent: entry.returnPct.unavailable == nil ? entry.returnPct.pct : nil,
                font: .rowValue
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
            }
        } else if isUnavailable || positions == nil {
            Text("This trader's positions aren't public.")
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
        } else if let positions, positions.positions.isEmpty {
            Text("All cash right now.")
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
        } else if let positions {
            positionList(positions)
                .blur(radius: isPro ? 0 : 9)
                .allowsHitTesting(isPro)
                .accessibilityHidden(!isPro)
                .overlay {
                    if !isPro { lockedOverlay }
                }
        }
    }

    private func positionList(_ positions: PaperTraderPositions) -> some View {
        VStack(spacing: 0) {
            ForEach(positions.positions) { position in
                HStack(spacing: Space.s12) {
                    TokenAvatar(mint: position.tokenMint, symbol: position.symbol, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(position.symbol ?? "Unknown")
                            .font(.rowTitle)
                            .foregroundStyle(Color.textPrimary)
                        Text("\(PriceFormat.percentPlain(position.sharePct)) of portfolio")
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    ChangeText(percent: position.unrealizedReturnPct, font: .rowValue)
                }
                .frame(minHeight: 56)
            }
            HStack {
                Text("Cash")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(PriceFormat.percentPlain(positions.cashSharePct))
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, Space.s8)
        }
    }

    private var lockedOverlay: some View {
        VStack(spacing: Space.s12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(Color.accent)
            Text("See what #\(entry.rank) is holding")
                .font(.rowTitle)
                .foregroundStyle(Color.textPrimary)
            Button("Unlock with Pro") { showsPaywall = true }
                .buttonStyle(.accent)
                .accessibilityIdentifier("trader.unlockPositions")
        }
        .padding(Space.s20)
    }

    private func load() async {
        isLoading = positions == nil
        do {
            positions = try await LeaderboardAPI.traderPositions(portfolioId: entry.portfolioId)
            isUnavailable = false
        } catch {
            isUnavailable = true
        }
        isLoading = false
    }
}
