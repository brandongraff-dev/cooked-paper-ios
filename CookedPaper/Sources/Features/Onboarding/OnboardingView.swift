import SwiftUI

/// Shown once on first launch, before the paywall. Each page previews a real piece
/// of the product on a neutral card — no decoration. `RootView` owns the
/// `hasSeenOnboarding` flag; this view only reports completion.
struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            preview: .balance,
            title: "Start with $10,000",
            detail: "Practice on live market prices with virtual cash. Nothing here is real money."
        ),
        OnboardingPage(
            preview: .chart,
            title: "Read the chart, make the call",
            detail: "Clean price charts, one-tap buys and sells, instant fills."
        ),
        OnboardingPage(
            preview: .leaderboard,
            title: "See how you stack up",
            detail: "Track your P&L and win rate, and climb the monthly leaderboard."
        ),
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    OnboardingPageView(page: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageIndicator
                .padding(.vertical, Space.s24)

            Button(isLastPage ? "Get started" : "Continue") {
                Haptics.tap()
                if isLastPage {
                    onFinished()
                } else {
                    withAnimation(Motion.standard) { page += 1 }
                }
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier(isLastPage ? "onboarding.getStarted" : "onboarding.next")
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s8)
        }
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
    }

    private var pageIndicator: some View {
        HStack(spacing: Space.s8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.textPrimary : Color.textTertiary)
                    .frame(width: 6, height: 6)
            }
        }
        .animation(Motion.standard, value: page)
        .accessibilityHidden(true)
    }
}

private enum OnboardingPreview {
    case balance, chart, leaderboard
}

private struct OnboardingPage {
    let preview: OnboardingPreview
    let title: String
    let detail: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            Spacer(minLength: Space.s24)

            Group {
                switch page.preview {
                case .balance: BalancePreview()
                case .chart: ChartPreview()
                case .leaderboard: LeaderboardPreview()
                }
            }
            .padding(Space.s20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.s12) {
                Text(page.title)
                    .font(.appLargeTitle)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.detail)
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.margin)
    }
}

private struct BalancePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            HStack(spacing: Space.s8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color.accentFlame)
                Text("Paper balance")
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
            }
            Text("$10,000.00")
                .heroPriceStyle()
                .foregroundStyle(Color.textPrimary)
            Text("Ready to trade")
                .font(.rowSubvalue)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

private struct ChartPreview: View {
    private let values: [Double] = [
        1.62, 1.58, 1.55, 1.57, 1.52, 1.54, 1.6, 1.58, 1.66, 1.7, 1.68, 1.74, 1.79, 1.77, 1.83,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(spacing: Space.s12) {
                MonogramAvatar(text: "WIF", size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("WIF")
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("$1.83")
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                ChangeText(percent: Decimal(string: "12.96"))
            }
            PriceLineChart(values: values, selectedIndex: .constant(nil))
                .frame(height: 120)
                .allowsHitTesting(false)
        }
    }
}

private struct LeaderboardPreview: View {
    private let rows: [(rank: Int, name: String, change: String)] = [
        (1, "degenwizard", "184.21"),
        (2, "solsniper", "122.40"),
        (3, "you", "97.12"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                HStack(spacing: Space.s12) {
                    Text("\(row.rank)")
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 16, alignment: .leading)
                    MonogramAvatar(text: row.name, size: 32)
                    Text(row.name)
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    ChangeText(percent: Decimal(string: row.change))
                }
                .frame(height: 52)
                if index < rows.count - 1 {
                    RowSeparator(leadingInset: 16 + Space.s12 + 32 + Space.s12)
                }
            }
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
