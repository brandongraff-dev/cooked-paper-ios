import SwiftUI
import UIKit

// Texture: film grain over glass surfaces, and solid gunmetal for buttons and
// hardware-like chips. No gradients anywhere.

// MARK: - Grain

/// A tile of monochrome noise, made once per launch and repeated.
enum Grain {
    static let image: UIImage = {
        let size = 96
        var pixels = [UInt8](repeating: 0, count: size * size)
        var generator = SystemRandomNumberGenerator()
        for index in pixels.indices {
            pixels[index] = UInt8.random(in: 0...255, using: &generator)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cgImage = CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage, scale: 2, orientation: .up)
    }()
}

/// Film grain laid over a surface. Overlay-blended, so it lifts highlights and deepens
/// shadows instead of graying everything.
struct GrainOverlay: View {
    var opacity: Double = 0.07

    var body: some View {
        Image(uiImage: Grain.image)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

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
