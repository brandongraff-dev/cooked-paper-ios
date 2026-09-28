import SwiftUI

/// Liquid Glass (iOS 26+) is the system's floating-navigation-layer material —
/// Apple's own guidance is explicit that it belongs on controls that sit *above*
/// content (tab bars, toolbars, floating actions, sheets, chips), never on the
/// content layer itself (this app's dense position/discover/leaderboard rows and the
/// candlestick chart's plot area stay solid `Terminal` surfaces on purpose).
///
/// This app's deployment target is iOS 17, so every use goes through the helpers
/// below rather than a bare `.glassEffect()` call: below iOS 26 they fall back to
/// this app's existing translucent-material look, so nothing here is a hard floor.
extension View {
    /// The general-purpose glass surface: chips, badges, floating chart overlays,
    /// inline pill controls. Pre-26, this renders as this app's existing
    /// `.ultraThinMaterial`-over-hairline treatment, so nothing regresses visually on
    /// an unsupported OS — it just doesn't get the refractive material.
    @ViewBuilder
    func cookedGlass(
        tint: Color? = nil,
        interactive: Bool = false,
        in shape: some InsettableShape = Capsule()
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(cookedGlassConfiguration(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(CookedColor.Terminal.border, lineWidth: 1))
        }
    }
}

@available(iOS 26.0, *)
private func cookedGlassConfiguration(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

/// Groups sibling glass surfaces so they share one sampling pass and can morph into
/// each other (e.g. a feed picker's chips) — Apple's own performance guidance is
/// explicit that un-grouped adjacent glass views render less efficiently. A no-op
/// passthrough below iOS 26, so call sites never need their own availability check
/// just to wrap children in this.
struct CookedGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
