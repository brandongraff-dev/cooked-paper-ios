import AVFoundation
import CoreVideo
import SwiftUI
import UIKit

/// A 15-second vertical clip of a Crash Replay run, made on device: the chart plays
/// forward with your moves on it for 12 seconds, then the verdict stamp holds for 3.
/// 720×1280 H.264 at 24 fps, written to a temporary file for the share sheet.
///
/// Frames are SwiftUI views rendered with `ImageRenderer` and appended through an
/// `AVAssetWriterInputPixelBufferAdaptor`, all on the main actor (the renderer needs it).
@MainActor
enum ReplayClipExporter {
    static let size = CGSize(width: 720, height: 1280)
    static let fps: Int32 = 24
    static let playSeconds = 12
    static let holdSeconds = 3

    enum ExportError: Error { case writer, frame }

    static func export(
        candles: [[Double]],
        actions: [ReplayAction],
        result: ReplayResult,
        number: Int
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cooked-crash-\(number)-\(UUID().uuidString.prefix(6)).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw ExportError.writer }
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.writer }
        writer.startSession(atSourceTime: .zero)

        let playFrames = Int(fps) * playSeconds
        let totalFrames = playFrames + Int(fps) * holdSeconds
        for frame in 0..<totalFrames {
            let shown = frame < playFrames
                ? max(1, Int((Double(frame + 1) / Double(playFrames)) * Double(candles.count)))
                : candles.count
            let view = ReplayClipFrame(
                candles: Array(candles.prefix(shown)),
                actions: actions.filter { $0.candle < shown },
                result: result,
                number: number,
                showsVerdict: frame >= playFrames
            )
            guard let buffer = pixelBuffer(for: view) else { throw ExportError.frame }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }

        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw ExportError.writer }
        return url
    }

    private static func pixelBuffer(for view: ReplayClipFrame) -> CVPixelBuffer? {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width / 2, height: size.height / 2)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: size.width / 2, height: size.height / 2)
        guard let image = renderer.cgImage else { return nil }

        var buffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attributes,
            &buffer
        )
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

/// One frame of the clip, laid out on a 360×640 canvas and rendered at 2×.
struct ReplayClipFrame: View {
    let candles: [[Double]]
    let actions: [ReplayAction]
    let result: ReplayResult
    let number: Int
    let showsVerdict: Bool

    var body: some View {
        ZStack {
            ShareCardStyle.background
            RadialGradient(colors: [ShareCardStyle.glow.opacity(0.3), .clear], center: .top, startRadius: 0, endRadius: 360)
            VStack(alignment: .leading, spacing: 14) {
                Text(showsVerdict ? result.reveal.name.uppercased() : "MYSTERY CRASH #\(number)")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.white.opacity(0.75))
                Text(showsVerdict ? result.reveal.date : "Could you survive it?")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                CrashReplayChart(candles: candles, actions: actions)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text("Me \(ShareCardFormat.pnl(result.returnPct))")
                        .foregroundStyle(result.returnPct < 0 ? Color.negative : Color.positive)
                    Spacer()
                    Text("Hold \(ShareCardFormat.pnl(result.holdReturnPct))")
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .opacity(showsVerdict ? 1 : 0)
                HStack {
                    BrandWordmark(height: 18)
                    Spacer()
                    Text("Paper game · cooked.trade")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .padding(24)

            if showsVerdict {
                Text(result.survived ? "SURVIVED" : "COOKED")
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(result.survived ? Color.positive : Color.negative, in: RoundedRectangle(cornerRadius: 18))
                    .rotationEffect(.degrees(-8))
            }
        }
    }
}
