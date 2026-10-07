import SwiftUI

// Drawn icons for the Play tiles: a live beacon and a crash on a screen.
// Flat solid colors (a lighter face and a darker edge for shape), no gradients, no grain.

private extension Color {
    static let liveRed = Color(rgb: 0xFF3B30)
}

/// A red dot with radio waves either side; the dot breathes unless motion is reduced.
struct LiveBeaconIcon: View {
    var height: CGFloat = 52

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let dot = height * 0.36
        ZStack {
            Circle()
                .fill(Color.liveRed.opacity(0.3))
                .frame(width: dot, height: dot)
                .scaleEffect(pulse ? 1.7 : 1)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(Color.liveRed)
                .frame(width: dot, height: dot)
            ForEach([0.62, 0.95], id: \.self) { scale in
                Waves()
                    .stroke(Color.white.opacity(scale < 0.7 ? 0.55 : 0.3),
                            style: StrokeStyle(lineWidth: height * 0.07, lineCap: .round))
                    .frame(width: height * 1.35 * scale, height: height * scale)
            }
        }
        .frame(width: height * 1.4, height: height)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, ProcessInfo.processInfo.environment["UITEST_STILL_FRAMES"] != "1" else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    /// A pair of arcs facing out, left and right.
    private struct Waves: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let r = rect.height / 2
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let dx = rect.width / 2 - r
            path.addArc(center: CGPoint(x: center.x - dx, y: center.y), radius: r,
                        startAngle: .degrees(140), endAngle: .degrees(220), clockwise: false)
            path.move(to: CGPoint(x: center.x + dx + r * cos(.pi * -40 / 180), y: center.y + r * sin(.pi * -40 / 180)))
            path.addArc(center: CGPoint(x: center.x + dx, y: center.y), radius: r,
                        startAngle: .degrees(-40), endAngle: .degrees(40), clockwise: false)
            return path
        }
    }
}

/// A small screen with a price line that drifts, falls off a cliff and bounces.
struct CrashScreenIcon: View {
    var height: CGFloat = 52

    var body: some View {
        let w = height * 1.6
        let shape = RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
        ZStack {
            shape.fill(Color.metalMid)
            shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
            Canvas { context, size in
                let inset: CGFloat = size.height * 0.18
                let box = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
                for row in 1...2 {
                    let y = box.minY + box.height * CGFloat(row) / 3
                    context.stroke(Path { $0.move(to: CGPoint(x: box.minX, y: y)); $0.addLine(to: CGPoint(x: box.maxX, y: y)) },
                                   with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
                let ys: [CGFloat] = [0.15, 0.25, 0.1, 0.22, 0.18, 0.75, 0.9, 0.72, 0.8]
                var line = Path()
                for (i, y) in ys.enumerated() {
                    let p = CGPoint(x: box.minX + box.width * CGFloat(i) / CGFloat(ys.count - 1), y: box.minY + box.height * y)
                    if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                context.stroke(line, with: .color(.liveRed), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                let end = CGPoint(x: box.maxX, y: box.minY + box.height * ys.last!)
                context.fill(Path(ellipseIn: CGRect(x: end.x - 3.5, y: end.y - 3.5, width: 7, height: 7)), with: .color(.liveRed))
            }
        }
        .frame(width: w, height: height)
        .accessibilityHidden(true)
    }
}
