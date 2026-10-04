import SwiftUI

extension EnvironmentValues {
    /// False for the app shell's three hidden tab stacks. They stay alive (and so
    /// never see `onDisappear`) to keep their navigation and scroll state, so this
    /// is how a screen knows it's actually the one on display.
    @Entry var isSelectedTab: Bool = true
}

extension View {
    /// Calls `action` every `interval` seconds while this view is on screen, in the
    /// selected tab, with the app active — and straight away when it comes back to
    /// any of those after the interval has passed or the app was backgrounded. The
    /// action should refresh silently: no loading state, keep what's shown on
    /// failure.
    func autoRefresh(every interval: TimeInterval, action: @escaping @MainActor () async -> Void) -> some View {
        modifier(AutoRefreshModifier(interval: interval, action: action))
    }
}

private struct AutoRefreshModifier: ViewModifier {
    let interval: TimeInterval
    let action: @MainActor () async -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSelectedTab) private var isSelectedTab
    /// Starts at creation, which is when the screen did its own first load.
    @State private var lastRefresh = Date()
    @State private var wasBackgrounded = false

    private var isLive: Bool { scenePhase == .active && isSelectedTab }

    func body(content: Content) -> some View {
        content
            // Cancelled whenever the view disappears or `isLive` flips, so the loop
            // only ever runs while the screen is visible and the app is active.
            .task(id: isLive) {
                guard isLive else { return }
                if wasBackgrounded || Date().timeIntervalSince(lastRefresh) >= interval {
                    wasBackgrounded = false
                    await run()
                }
                while !Task.isCancelled {
                    let wait = max(1, interval - Date().timeIntervalSince(lastRefresh))
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled else { return }
                    await run()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { wasBackgrounded = true }
            }
    }

    private func run() async {
        lastRefresh = Date()
        await action()
    }
}
