import SwiftUI

/// A one-shot cascading fade+rise for a list's first screenful of rows, played once
/// when a row first appears as its list moves from loading/empty to populated. SwiftUI
/// reuses row identity and re-fires `.onAppear` as `List` rows scroll in and out, so a
/// plain per-row `@State` here would replay the cascade on every scroll — chaotic, not
/// polished. The "already played" flag has to outlive this modifier's own view, which
/// is why it lives in the parent screen's own `Set` (bound in) rather than as local
/// state: each of the four list screens declares `@State private var animatedRowIDs:
/// Set<String> = []` and passes `$animatedRowIDs` down to every row.
struct StaggeredEntrance<ID: Hashable>: ViewModifier {
    let index: Int
    let id: ID
    @Binding var animatedIDs: Set<ID>

    /// Past this many rows the cascade would take over a second to finish rendering —
    /// slow, not delightful — so later rows just appear with no fade or delay.
    private static var maxAnimatedRows: Int { 8 }
    /// Per-row delay inside the cascade. Below ~30ms it reads as one simultaneous
    /// event; above ~40ms the list starts to feel like it's loading row-by-row.
    private static var staggerInterval: Double { 0.035 }

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 6)
            .onAppear {
                guard !animatedIDs.contains(id) else {
                    isVisible = true
                    return
                }
                animatedIDs.insert(id)
                guard index < Self.maxAnimatedRows else {
                    isVisible = true
                    return
                }
                withAnimation(CookedMotion.calm.delay(Double(index) * Self.staggerInterval)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    /// Applies the shared row-entrance cascade. `id` is the row's own stable identity
    /// (its `Identifiable.id`); `animatedIDs` is the parent screen's already-animated
    /// set, passed as a binding so every row mutates the same set rather than each
    /// keeping a private copy that can't remember what already played.
    func staggeredEntrance<ID: Hashable>(index: Int, id: ID, animatedIDs: Binding<Set<ID>>) -> some View {
        modifier(StaggeredEntrance(index: index, id: id, animatedIDs: animatedIDs))
    }
}
