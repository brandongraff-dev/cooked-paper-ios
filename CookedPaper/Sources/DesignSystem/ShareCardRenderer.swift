import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Share cards: one-tap images (trade, duel result, Daily Call streak) rendered on
// device with `ImageRenderer` and shared through `ShareLink`. Every card is drawn on
// the same 360×450pt canvas and rendered at 3× — a 1080×1350 (4:5) PNG, the size
// feeds crop least. No server round trip: the only network use is the token logo,
// fetched the same way `TokenAvatar` does and falling back to the monogram.
//
// The canvas is the one place the app uses a glow: it is a poster, not a screen, and
// echoes the landing page's silk ribbon (violet on near-black). Inside it the
// in-app rules still hold — green up, red down, type for hierarchy.

// MARK: - Style

enum ShareCardStyle {
    /// The canvas in points; `ShareCardRenderer.scale` turns it into 1080×1350 px.
    static let size = CGSize(width: 360, height: 450)
    /// A 9:16 story (Instagram, TikTok, Snapchat): 1080×1920 px at the same scale.
    static let storySize = CGSize(width: 360, height: 640)
    /// The landing page's background.
    static let background = Color(rgb: 0x0A0A0D)
    /// The landing page's ribbon accent.
    static let glow = Color(rgb: 0xB4A6FF)
    static let footer = "Paper money. Results simulated. cooked.trade"
}

// MARK: - Formatting

/// The text on the cards, kept apart from the views so it can be tested.
enum ShareCardFormat {
    static let minus = PriceFormat.minus

    /// Percent return from an entry price to a later one; nil when the entry isn't
    /// a positive price (nothing measurable — show "—", never 0%).
    static func returnPct(entry: Decimal, exit: Decimal) -> Decimal? {
        guard entry > 0 else { return nil }
        return (exit - entry) / entry * 100
    }

    /// The headline PnL: "+42.10%", "−8.03%", "+184.2%", "+1,204%". Fewer decimals
    /// as the number grows, so a moonshot still fits on one line. A real minus sign;
    /// zero reads "+0.00%"; nil reads "—".
    static func pnl(_ percent: Decimal?, locale: Locale = .current) -> String {
        guard let percent else { return "—" }
        let double = NSDecimalNumber(decimal: percent).doubleValue
        let magnitude = abs(double)
        let digits: Int
        if magnitude >= 1000 {
            digits = 0
        } else if magnitude >= 100 {
            digits = 1
        } else {
            digits = 2
        }
        let number = magnitude.formatted(.number.precision(.fractionLength(digits)).locale(locale))
        // A tiny loss that rounds to 0.00 reads as flat, not "−0.00%".
        let roundsToZero = number.allSatisfy { !$0.isNumber || $0 == "0" }
        let sign = double < 0 && !roundsToZero ? minus : "+"
        return sign + number + "%"
    }

    /// "$WIF" from "WIF" or "$WIF"; the mint's first six characters when there's
    /// no symbol.
    static func symbol(_ raw: String?, mint: String) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(mint.prefix(6)) }
        return trimmed.hasPrefix("$") ? trimmed : "$" + trimmed
    }

    /// "cooked.trade/d/<code>" for a duel invite, nil without a code.
    static func duelLink(code: String?) -> String? {
        let trimmed = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "cooked.trade/d/\(trimmed)"
    }

    /// "https://cooked.trade/d/<code>" for share text, nil without a code. The
    /// card shows the shorter `duelLink`; the message carries the full https URL so
    /// it is tappable everywhere and opens the app as a universal link.
    static func duelURL(code: String?) -> String? {
        duelLink(code: code).map { "https://\($0)" }
    }

    /// WIN / LOSS / DRAW.
    static func verdict(_ outcome: DuelOutcome) -> String {
        switch outcome {
        case .won: "WIN"
        case .lost: "LOSS"
        case .draw: "DRAW"
        }
    }

    /// "1 day streak" / "7 day streak".
    static func streak(_ days: Int) -> String {
        "\(days) day streak"
    }
}

// MARK: - Canvas

/// The frame every card shares: wordmark and a tag on top, the card's content, the
/// disclosure footer, on the violet-glow background.
struct ShareCardCanvas<Content: View>: View {
    /// The small tag in the top corner: "PAPER TRADE", "PAPER DUEL", "DAILY CALL".
    let tag: String
    let content: Content

    init(tag: String, @ViewBuilder content: () -> Content) {
        self.tag = tag
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                BrandWordmark(height: 22)
                Spacer(minLength: Space.s8)
                Text(tag)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(ShareCardStyle.glow)
                    .padding(.horizontal, Space.s8)
                    .padding(.vertical, Space.s4)
                    .overlay(
                        Capsule().strokeBorder(ShareCardStyle.glow.opacity(0.5), lineWidth: 1)
                    )
            }

            Spacer(minLength: Space.s16)
            content
            Spacer(minLength: Space.s16)

            HStack(spacing: Space.s8) {
                BrandMark(height: 14, color: .textTertiary)
                Text(ShareCardStyle.footer)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(Space.s24)
        .frame(width: ShareCardStyle.size.width, height: ShareCardStyle.size.height)
        .background(ShareCardBackground())
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

/// Near-black with a soft violet bloom top-right, a fainter one bottom-left, and a
/// thin ribbon of light sweeping across: the landing page's silk, held still.
struct ShareCardBackground: View {
    var body: some View {
        ZStack {
            ShareCardStyle.background
            RadialGradient(
                colors: [ShareCardStyle.glow.opacity(0.30), ShareCardStyle.glow.opacity(0)],
                center: UnitPoint(x: 0.95, y: 0.02),
                startRadius: 0,
                endRadius: 300
            )
            RadialGradient(
                colors: [ShareCardStyle.glow.opacity(0.12), ShareCardStyle.glow.opacity(0)],
                center: UnitPoint(x: 0.0, y: 1.0),
                startRadius: 0,
                endRadius: 260
            )
            ShareCardRibbon()
                .stroke(ribbonGradient(peak: 0.35), lineWidth: 26)
                .blur(radius: 18)
            ShareCardRibbon()
                .stroke(ribbonGradient(peak: 0.45), lineWidth: 1)
        }
    }

    private func ribbonGradient(peak: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                ShareCardStyle.glow.opacity(0),
                ShareCardStyle.glow.opacity(peak),
                ShareCardStyle.glow.opacity(0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// One loose S-curve through the upper part of the card.
struct ShareCardRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 20, y: rect.minY + rect.height * 0.34))
        path.addCurve(
            to: CGPoint(x: rect.maxX + 20, y: rect.minY + rect.height * 0.12),
            control1: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.44)
        )
        return path
    }
}

/// A token logo already in memory (ImageRenderer can't wait on `AsyncImage`),
/// else the monogram.
struct ShareCardTokenLogo: View {
    let image: UIImage?
    let symbol: String
    var size: CGFloat = 52

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            MonogramAvatar(text: symbol, size: size)
        }
    }
}

// MARK: - Rendering

enum ShareCardRenderer {
    /// 360×450pt at 3× = 1080×1350px.
    static let scale: CGFloat = 3

    /// The card as PNG data, or nil if rendering failed. Fixed Dynamic Type and a
    /// dark scheme, so the image is the same on every device.
    static func png<Card: View>(_ card: Card, size: CGSize = ShareCardStyle.size) -> Data? {
        let content = card
            .frame(width: size.width, height: size.height)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }
}

/// Token logos for cards, kept for the session so re-rendering a card (a live
/// price moved) doesn't refetch.
enum ShareCardLogoCache {
    private static var images: [URL: UIImage] = [:]

    static func image(for url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let cached = images[url] { return cached }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        guard let result = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard let image = UIImage(data: result.0) else { return nil }
        images[url] = image
        return image
    }
}

/// A rendered card, handed to the share sheet as a PNG file.
nonisolated struct ShareCardImage: Transferable {
    let png: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in
            image.png
        }
    }
}

// MARK: - Share button

/// "Share" for a card: renders `card` ahead of the tap whenever `id` changes
/// (debounced, so a live price doesn't re-render every tick) and shares the PNG with
/// a short message ending in cooked.trade. Shows a disabled button until the first
/// render lands. The caller sets the button style.
struct ShareImageButton<ID: Hashable, Card: View>: View {
    /// Re-renders when this changes; pass the card's model.
    let id: ID
    /// The share sheet's title and the message's subject.
    let title: String
    /// Text shared beside the image; should mention cooked.trade.
    let message: String
    /// The token logo to fetch before rendering, if the card shows one.
    var logoURL: URL? = nil
    /// Icon-only, for a toolbar or a card header.
    var compact = false
    var label = "Share card"
    /// The canvas: the 4:5 card by default, `ShareCardStyle.storySize` for a story.
    var size = ShareCardStyle.size
    let card: (UIImage?) -> Card

    @State private var image: ShareCardImage?
    @State private var preview: Image?

    init(
        id: ID,
        title: String,
        message: String,
        logoURL: URL? = nil,
        compact: Bool = false,
        label: String = "Share card",
        size: CGSize = ShareCardStyle.size,
        @ViewBuilder card: @escaping (UIImage?) -> Card
    ) {
        self.size = size
        self.id = id
        self.title = title
        self.message = message
        self.logoURL = logoURL
        self.compact = compact
        self.label = label
        self.card = card
    }

    var body: some View {
        Group {
            if let image {
                ShareLink(
                    item: image,
                    subject: Text(title),
                    message: Text(message),
                    preview: SharePreview(title, image: preview ?? Image(systemName: "photo"))
                ) {
                    labelView
                }
            } else {
                Button {} label: { labelView }
                    .disabled(true)
            }
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier("share.image")
        .task(id: id) { await render() }
    }

    @ViewBuilder
    private var labelView: some View {
        if compact {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(Color.textPrimary)
        } else {
            Label(label, systemImage: "square.and.arrow.up")
        }
    }

    private func render() async {
        // Debounce: a newer id cancels this task before it renders.
        try? await Task.sleep(for: .milliseconds(image == nil ? 50 : 600))
        guard !Task.isCancelled else { return }
        let logo = await ShareCardLogoCache.image(for: logoURL)
        guard !Task.isCancelled else { return }
        guard let data = ShareCardRenderer.png(card(logo), size: size) else { return }
        image = ShareCardImage(png: data)
        preview = UIImage(data: data).map { Image(uiImage: $0) }
    }
}
