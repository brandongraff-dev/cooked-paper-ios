import Combine
import SwiftUI
import UIKit

struct AppShellView: View {
    let portfolioStore = PortfolioStore.shared
    let router = DeepLinkRouter.shared
    let tabBarVisibility = FloatingTabBarVisibility.shared

    private var deepLinkTarget: DeepLinkTarget? {
        router.pendingTokenMint.map(DeepLinkTarget.init)
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
                .environment(\.tabBarInset, tabBarVisibility.isHidden ? 0 : FloatingTabBar.height + Space.s8)
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
                .allowsHitTesting(!isKeyboardVisible && !tabBarVisibility.isHidden)
                .animation(Motion.standard, value: isKeyboardVisible)
                // Slides off the bottom edge under a pushed screen that hides it.
                .offset(y: tabBarVisibility.isHidden ? FloatingTabBar.height * 2 : 0)
                .accessibilityHidden(tabBarVisibility.isHidden)
                .zIndex(2)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onChange(of: selection) { _, _ in
            // A search field focused in the tab being left must not keep its
            // keyboard up over the next one.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .tint(Color.accent)
        .task {
            await portfolioStore.bootstrapIfNeeded()
        }
        .sheet(item: deepLinkBinding) { target in
            NavigationStack {
                TokenDetailView(mint: target.mint)
            }
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .discover: DiscoverView()
        case .portfolio: PortfolioView()
        case .leaderboard: LeaderboardView()
        case .settings: SettingsView()
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case discover, portfolio, leaderboard, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "Discover"
        case .portfolio: "Portfolio"
        case .leaderboard: "Leaderboard"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .discover: "safari"
        case .portfolio: "wallet.bifold"
        case .leaderboard: "trophy"
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

/// Liquid Glass on iOS 26, a solid elevated capsule with a hairline before that.
private struct TabBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(Color.appSurfaceElevated, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.appSeparator, lineWidth: 1))
        }
    }
}

private struct DeepLinkTarget: Identifiable {
    let mint: String
    var id: String { mint }
}
