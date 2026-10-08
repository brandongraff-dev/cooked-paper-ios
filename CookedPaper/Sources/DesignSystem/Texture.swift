import SwiftUI

// Solid gunmetal for buttons and hardware-like chips. No gradients, no grain.

// MARK: - Metal

extension Color {
    /// Gunmetal: the solid fill of metal surfaces.
    static let metalMid = Color(rgb: 0x2A2D34)
}

/// Solid gunmetal with a hairline edge.
private struct MetalSurface<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Color.metalMid))
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

extension View {
    /// Solid gunmetal in `shape` (a capsule by default).
    func metalSurface<S: InsettableShape>(_ shape: S) -> some View {
        modifier(MetalSurface(shape: shape))
    }

    func metalSurface() -> some View {
        modifier(MetalSurface(shape: Capsule()))
    }
}
