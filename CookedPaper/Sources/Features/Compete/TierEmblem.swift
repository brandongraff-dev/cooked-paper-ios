import SwiftUI

/// The challenge tiers, by rank: Rookie ($10K), Pro ($50K), Elite ($100K).
enum ChallengeRank {
    static func level(_ tier: String) -> Int {
        switch tier {
        case "100k": 3
        case "50k": 2
        default: 1
        }
    }

    static func name(_ tier: String) -> String {
        switch level(tier) {
        case 3: "Elite"
        case 2: "Pro"
        default: "Rookie"
        }
    }
}

/// A rank badge drawn for the challenges: a hexagon with one, two or three chevrons,
/// like a service stripe. Lit (accent fill, white marks, a halo ring) for a tier you
/// can take or have passed; unlit (gunmetal, gray marks) for one you didn't.
struct TierEmblem: View {
    let level: Int
    var size: CGFloat = 52
    var lit: Bool = true

    var body: some View {
        ZStack {
            // A thin outer ring, offset from the badge, so it reads as a medal.
            Hexagon()
                .stroke(lit ? Color.accent.opacity(0.45) : Color.white.opacity(0.12), lineWidth: 1.5)
                .frame(width: size, height: size)
            Hexagon()
                .fill(lit ? Color.accent : Color.metalMid)
                .overlay(Hexagon().stroke(Color.white.opacity(lit ? 0.35 : 0.12), lineWidth: 1))
                .frame(width: size * 0.8, height: size * 0.8)
            Chevrons(count: max(1, min(level, 3)))
                .stroke(
                    lit ? Color.accentInk : Color.white.opacity(0.4),
                    style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 0.38, height: size * 0.36)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A pointy-top hexagon filling its rect.
private struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.933, y: rect.minY + h * 0.25))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.933, y: rect.minY + h * 0.75))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.5, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.067, y: rect.minY + h * 0.75))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.067, y: rect.minY + h * 0.25))
        path.closeSubpath()
        return path
    }
}

/// One to three upward chevrons, stacked and centered in the rect.
private struct Chevrons: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rise = rect.height * 0.32
        let gap = count == 1 ? 0 : (rect.height - rise) / CGFloat(count - 1)
        let top = count == 1 ? rect.midY - rise / 2 : rect.minY
        for i in 0..<count {
            let y = top + CGFloat(i) * gap
            path.move(to: CGPoint(x: rect.minX, y: y + rise))
            path.addLine(to: CGPoint(x: rect.midX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y + rise))
        }
        return path
    }
}

/// The fail line to the pass line as one quiet track, with a marker where you stand
/// (0 = out, 1 = passed). No traffic-light colors: the labels say which end is which.
struct ChallengeRail: View {
    let marker: Double
    var fill: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let x = geometry.size.width * min(max(marker, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                if fill {
                    Capsule().fill(Color.accent).frame(width: max(x, 6), height: 4)
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .offset(x: x - 6)
            }
        }
        .frame(height: 12)
    }
}
