#!/usr/bin/env swift
//
// GenerateIcon.swift
//
// Renders the Cooked Paper App Store icon (a candlestick pair) to a real
// 1024x1024 PNG using SwiftUI's ImageRenderer. Run on a Mac with:
//
//   swift Scripts/GenerateIcon.swift
//
// from apps/ios/CookedPaper, or make it executable and run it directly:
//
//   chmod +x Scripts/GenerateIcon.swift && Scripts/GenerateIcon.swift
//
// Requires macOS 13+ (ImageRenderer) and a Swift toolchain with SwiftUI/AppKit,
// i.e. Xcode 14+'s command-line tools. Writes straight to
// Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png.

import SwiftUI
import AppKit
import CoreGraphics
import Foundation

// MARK: - Icon artwork

/// Colors ported by hand from Sources/DesignSystem/Colors.swift. This script runs
/// outside the app target (plain `swift` invocation, no Xcode project), so it can't
/// import CookedColor directly — keep these three values in sync with that file.
private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private enum IconColor {
    static let graphite = Color(hex: 0x0F0E0D) // CookedColor.Product.graphite
    static let graphiteHi = Color(hex: 0x1A1917)
    static let graphiteLo = Color(hex: 0x0B0A09)
    static let buy = Color(hex: 0x16C784) // CookedColor.Terminal.buy
    static let sell = Color(hex: 0xFF5D67) // CookedColor.Terminal.sell
}

private let canvasSize: CGFloat = 1024

private struct Candlestick: View {
    let color: Color
    let bodyHeight: CGFloat
    let yOffset: CGFloat

    private let wickWidth = canvasSize * 0.06
    private let wickHeight = canvasSize * 0.60
    private let bodyWidth = canvasSize * 0.24

    var body: some View {
        ZStack {
            Capsule()
                .fill(color)
                .frame(width: wickWidth, height: wickHeight)

            RoundedRectangle(cornerRadius: canvasSize * 0.05, style: .continuous)
                .fill(color)
                .frame(width: bodyWidth, height: bodyHeight)
                .shadow(color: color.opacity(0.35), radius: canvasSize * 0.02, y: canvasSize * 0.01)
        }
        .offset(y: yOffset)
    }
}

private struct AppIconView: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [IconColor.graphiteHi, IconColor.graphiteLo],
                center: .center,
                startRadius: 0,
                endRadius: canvasSize * 0.75
            )

            HStack(spacing: canvasSize * 0.13) {
                Candlestick(color: IconColor.sell, bodyHeight: canvasSize * 0.28, yOffset: canvasSize * 0.08)
                Candlestick(color: IconColor.buy, bodyHeight: canvasSize * 0.32, yOffset: -canvasSize * 0.08)
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .background(IconColor.graphite)
    }
}

// MARK: - Rendering

private enum IconGenerationError: Error {
    case renderFailed
    case alphaStripFailed
    case pngEncodingFailed
}

@MainActor
private func renderToImage() -> CGImage? {
    let renderer = ImageRenderer(content: AppIconView())
    renderer.scale = 1.0
    renderer.proposedSize = ProposedViewSize(width: canvasSize, height: canvasSize)
    return renderer.cgImage
}

/// App Store icons must ship with no alpha channel. ImageRenderer's CGImage carries
/// one regardless of what the view draws, even when every pixel ends up fully
/// opaque, so re-composite into a context that has none before encoding the PNG.
private func stripAlphaChannel(from image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        return nil
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.pngEncodingFailed
    }
    try data.write(to: url, options: .atomic)
}

// MARK: - Entry point

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let cookedPaperRoot = scriptURL
    .deletingLastPathComponent() // Scripts/
    .deletingLastPathComponent() // CookedPaper/
let outputURL = cookedPaperRoot
    .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

do {
    guard let rendered = renderToImage() else {
        throw IconGenerationError.renderFailed
    }
    guard let opaque = stripAlphaChannel(from: rendered) else {
        throw IconGenerationError.alphaStripFailed
    }
    try writePNG(opaque, to: outputURL)
    let hasNoAlpha = opaque.alphaInfo == .noneSkipLast || opaque.alphaInfo == .noneSkipFirst || opaque.alphaInfo == .none
    print("Wrote \(opaque.width)x\(opaque.height) icon (alpha channel: \(hasNoAlpha ? "none" : "present")) to \(outputURL.path)")
} catch {
    FileHandle.standardError.write("Failed to generate app icon: \(error)\n".data(using: .utf8)!)
    exit(1)
}
