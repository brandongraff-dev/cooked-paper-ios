import SwiftUI
import UIKit

// Texture: what keeps the glass and the metal from looking like flat vector fills.
// Film grain over every glass surface, brushed gunmetal for buttons and hardware-like
// chips, and a slow sheen that crosses the few surfaces worth celebrating.

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
    /// Gunmetal, top to bottom: the brushed surface's three stops.
    static let metalHigh = Color(rgb: 0x4A4E58)
    static let metalMid = Color(rgb: 0x2A2D34)
    static let metalLow = Color(rgb: 0x1B1D22)
}

/// Brushed gunmetal: a vertical gradient, fine horizontal brushing, a soft specular
/// band, and a bevel (lit top edge, dark bottom edge).
private struct MetalSurface<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [.metalHigh, .metalMid, .metalLow],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // Brushing: the grain stretched sideways into fine streaks.
                    GrainOverlay(opacity: 0.16)
                        .scaleEffect(x: 12, y: 1, anchor: .center)
                        .clipShape(shape)
                    // A soft specular band across the upper third.
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0), location: 0.05),
                                .init(color: .white.opacity(0.10), location: 0.28),
                                .init(color: .white.opacity(0), location: 0.55),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.38), .white.opacity(0.06), .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
    }
}

extension View {
    /// Brushed gunmetal in `shape` (a capsule by default).
    func metalSurface<S: InsettableShape>(_ shape: S) -> some View {
        modifier(MetalSurface(shape: shape))
    }

    func metalSurface() -> some View {
        modifier(MetalSurface(shape: Capsule()))
    }
}

// MARK: - Sheen

/// A band of light that sweeps across the view every few seconds. For the one surface
/// on a screen worth celebrating (the main CTA, an offer, an unlocked badge). Static
/// under Reduce Motion and in screenshot runs.
private struct Sheen<S: Shape>: ViewModifier {
    let shape: S
    var period: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static var stillFrames: Bool { ProcessInfo.processInfo.environment["UITEST_STILL_FRAMES"] == "1" }

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion && !Self.stillFrames {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    // 0 → 1 over the first 30% of each period, then rest off-screen.
                    let phase = (t.truncatingRemainder(dividingBy: period)) / period
                    let progress = min(phase / 0.3, 1)
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        LinearGradient(
                            colors: [.white.opacity(0), .white.opacity(0.32), .white.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.35)
                        .rotationEffect(.degrees(20))
                        .offset(x: -width * 0.5 + progress * width * 1.6)
                        .blendMode(.plusLighter)
                    }
                    .clipShape(shape)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func sheen<S: Shape>(in shape: S, every period: Double = 4.5) -> some View {
        modifier(Sheen(shape: shape, period: period))
    }
}
