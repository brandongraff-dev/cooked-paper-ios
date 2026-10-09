import Combine
import SwiftUI
import UIKit

struct AppShellView: View {
    let portfolioStore = PortfolioStore.shared
    let router = DeepLinkRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    private var deepLinkTarget: DeepLinkTarget? {
        if let mint = router.pendingTokenMint { return .token(mint) }
        if let code = router.pendingDuelInviteCode { return .duelInvite(code) }
        if let id = router.pendingDuelId { return .duel(id) }
        if let code = router.pendingLeagueInviteCode { return .leagueInvite(code) }
        if let id = router.pendingLeagueId { return .league(id) }
        if router.showsAchievements { return .achievements }
        return nil
    }

    /// A custom binding rather than `$router.pendingTokenMint` directly: the setter
    /// runs on swipe-to-dismiss as well as programmatic dismissal, so `clear()` fires
    /// either way and a re-opened link with the same mint reliably re-triggers.
    private var deepLinkBinding: Binding<DeepLinkTarget?> {
        Binding(
            get: { deepLinkTarget },
            set: { newValue in
                if newValue == nil { router.clear() }
            }
        )
    }

    @State private var selection: AppTab = .discover
    @State private var isKeyboardVisible = false
    /// Once per account, on the first open after the free tier's full-access days end.
    @AppStorage("hasSeenFullAccessEnded") private var hasSeenFullAccessEnded = false
    @State private var showsFullAccessEnded = false

    /// Recounts today's free trades, and says so once when full access has ended.
    private func checkFreeTier() async {
        await FreeTier.shared.refresh()
        if FreeTier.shared.isLimited && !hasSeenFullAccessEnded {
            hasSeenFullAccessEnded = true
            showsFullAccessEnded = true
        }
    }

    var body: some View {
        // All four stacks stay alive (so each keeps its navigation and scroll
        // state); only the selected one is visible, hit-testable and in the
        // accessibility tree. This replaces the system tab bar entirely, so it can't
        // reappear on a pushed screen the way a hidden TabView bar can.
        ZStack(alignment: .bottom) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selection
                NavigationStack {
                    root(for: tab)
                }
                // Every screen in the stack (pushed ones too) reads this and keeps
                // its content and pinned bars clear of the floating tab bar.
                .environment(\.tabBarInset, FloatingTabBar.height + Space.s8)
                // Lets a screen's auto-refresh pause while its tab is hidden.
                .environment(\.isSelectedTab, isSelected)
                .opacity(isSelected ? 1 : 0)
                .allowsHitTesting(isSelected)
                .accessibilityHidden(!isSelected)
                .zIndex(isSelected ? 1 : 0)
            }

            // Its own layer, laid out ignoring the keyboard: while typing, the
            // keyboard covers the bar (as it does the system tab bar) instead of
            // pushing it up over the content.
            FloatingTabBar(selection: $selection)
                .padding(.bottom, Space.s4)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                // Steps aside while typing, as the system tab bar does.
                .opacity(isKeyboardVisible ? 0 : 1)
                .allowsHitTesting(!isKeyboardVisible)
                .animation(Motion.standard, value: isKeyboardVisible)
                .zIndex(2)

            // Unlock celebrations float over every tab and pushed screen.
            AchievementToastHost()
                .frame(maxHeight: .infinity, alignment: .top)
                .zIndex(3)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onChange(of: router.requestedTab) { _, tab in
            guard let tab else { return }
            router.clearTabRequest()
            guard tab != selection else { return }
            Haptics.selection()
            withAnimation(Motion.standard) { selection = tab }
        }
        .onChange(of: selection) { _, _ in
            // A search field focused in the tab being left must not keep its
            // keyboard up over the next one.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .tint(Color.accent)
        .task {
            await portfolioStore.bootstrapIfNeeded()
            await checkFreeTier()
        }
        // Unlocks earned while the app was away are celebrated on the way back in.
        .task {
            await AchievementCenter.shared.checkForUnseen()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard newPhase == .active, oldPhase == .background || oldPhase == .inactive else { return }
            Task { await AchievementCenter.shared.checkForUnseen() }
            Task { await checkFreeTier() }
        }
        .sheet(isPresented: $showsFullAccessEnded) {
            PaywallView(reason: .fullAccessEnded) { showsFullAccessEnded = false }
        }
        .sheet(item: deepLinkBinding) { target in
            switch target {
            case .token(let mint):
                NavigationStack {
                    TokenDetailView(mint: mint)
                }
                .presentationDragIndicator(.visible)
            case .duelInvite(let code):
                JoinDuelSheet(inviteCode: code)
            case .duel(let id):
                NavigationStack {
                    DuelDetailView(duelId: id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { router.clear() }
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            case .leagueInvite(let code):
                JoinLeagueSheet(initialCode: code)
            case .league(let id):
                NavigationStack {
                    LeagueDetailView(leagueId: id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { router.clear() }
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            case .achievements:
                NavigationStack {
                    AchievementsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { router.clear() }
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .discover: DiscoverView()
        case .portfolio: PortfolioView()
        case .compete: CompeteView()
        case .settings: SettingsView()
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case discover, portfolio, compete, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "Discover"
        case .portfolio: "Portfolio"
        case .compete: "Compete"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .discover: "safari"
        case .portfolio: "wallet.bifold"
        case .compete: "trophy"
        case .settings: "gearshape"
        }
    }
}

/// A compact floating bar: four icons in a capsule, the selected one in the accent
/// color on a small circle that slides between tabs. Sized to its icons rather than
/// stretched across the screen, so the selection circle stays snug.
private struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var namespace

    static let itemSize: CGFloat = 44
    static let inset: CGFloat = 6
    static let height: CGFloat = itemSize + inset * 2

    var body: some View {
        HStack(spacing: Space.s12) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    guard !isSelected else { return }
                    Haptics.selection()
                    withAnimation(Motion.standard) { selection = tab }
                } label: {
                    Image(systemName: tab.symbol)
                        .symbolVariant(isSelected ? .fill : .none)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
                        .frame(width: Self.itemSize, height: Self.itemSize)
                        .background {
                            if isSelected {
                                Circle()
                                    .fill(Color.selectedFill)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(Self.inset)
        .modifier(TabBarBackground())
    }
}

/// A solid elevated capsule with a hairline. Not glass: a translucent bar let the rows
/// scrolling beneath it show through its icons.
private struct TabBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.appSurfaceElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.appSeparator, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}

/// What a deep link (or a tapped push) opens over the tabs.
private enum DeepLinkTarget: Identifiable {
    case token(String)
    case duelInvite(String)
    case duel(String)
    case leagueInvite(String)
    case league(String)
    case achievements

    var id: String {
        switch self {
        case .token(let mint): "token-\(mint)"
        case .duelInvite(let code): "invite-\(code)"
        case .duel(let id): "duel-\(id)"
        case .leagueInvite(let code): "league-invite-\(code)"
        case .league(let id): "league-\(id)"
        case .achievements: "achievements"
        }
    }
}
