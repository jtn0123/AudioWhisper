import XCTest
import SwiftUI
import AppKit
import CoreGraphics
@testable import AudioWhisper

/// Lightweight snapshot helper built on XCTest + ImageRenderer.
///
/// **Baselines are environment-specific.** Comparison is exact-match on RGBA
/// bytes (modulo the per-call `tolerance:`), and SwiftUI rendering differs
/// between macOS releases — fonts, antialiasing and material rendering all move.
/// The committed baselines were recorded on the maintainer's machine, so they
/// are authoritative *there* and may not match a different macOS.
///
/// Consequences:
///  * Locally: opt in with `SNAPSHOT_TESTS=1 make test`. If your machine renders
///    differently, re-record with `SNAPSHOT_RECORD=1 make test` and inspect the
///    diff by eye before committing — do not re-record reflexively, that is how
///    a real regression gets blessed.
///  * In CI: the `snapshots` job is report-only for exactly this reason, and it
///    uploads its renders as a diagnostic artifact.
///
/// **Do not adopt CI renders as baselines.** That was this file's previous
/// advice and it is wrong. Measured 2026-08-01 against a real run: all 34 CI
/// renders diverged from the local ones by 19–100% of pixels, because the
/// runner draws AppKit-backed controls as the yellow "cannot render" placeholder
/// and drops materials entirely. Committing them would have replaced every
/// baseline with a picture of a broken render.
@MainActor
class SnapshotTestCase: XCTestCase {
    private let snapshotFolderName = "__Snapshots__"
    
    /// Enable recording by running tests with `SNAPSHOT_RECORD=1`.
    private var isRecording: Bool {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
    }

    private var isSnapshotTestingEnabled: Bool {
        isRecording || ProcessInfo.processInfo.environment["SNAPSHOT_TESTS"] == "1"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard isSnapshotTestingEnabled else {
            throw XCTSkip("Snapshot tests are disabled by default. Set SNAPSHOT_TESTS=1 (or SNAPSHOT_RECORD=1) to run them.")
        }
    }
    
    /// Renders `view` and compares it against the committed baseline.
    ///
    /// - Parameter tolerance: maximum fraction of pixels (0...1) allowed to
    ///   differ before the assertion fails. Defaults to `0` — exact match.
    ///
    ///   Most views render deterministically: 31 of 39 snapshots are
    ///   byte-identical across back-to-back recording runs on the same machine.
    ///   The waveform views are not. They animate, and `WaveformBars.updateLevels`
    ///   feeds `CGFloat.random(in:)` into bar heights, so a captured frame varies
    ///   by up to ~2% of pixels between runs. Those call sites pass a small
    ///   tolerance; everything else stays exact so real regressions still fail.
    func assertSnapshot<V: View>(
        _ view: V,
        named name: String,
        size: CGSize,
        colorScheme: ColorScheme = .light,
        scale: CGFloat = 2,
        tolerance: Double = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let content = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, colorScheme)
            // ImageRenderer draws ScrollView content as a flat rectangle, which
            // is what made 13 baselines blank. ScrollableContent honours this by
            // dropping the ScrollView wrapper so the content is actually drawn.
            .environment(\.flattensScrollViews, true)
            .environmentObject(WindowCoordinator.shared)
            .environment(MLXModelManager.shared)
            .environment(PermissionManager.shared)
        
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        
        guard let image = renderer.nsImage,
              let actualData = image.pngData() else {
            XCTFail("Failed to render snapshot \(name)", file: file, line: line)
            return
        }
        
        // A render that is one flat colour is not a regression test — it will
        // match its own baseline forever no matter what the view does. 13 of the
        // 39 committed baselines were exactly this (10 of them a SINGLE colour)
        // because `ImageRenderer` does not draw `ScrollView` content, and every
        // one of them had been passing since it was recorded.
        //
        // Checked before the recording branch too, so a blank baseline can never
        // be written in the first place.
        if let flat = dominantColorFraction(pngData: actualData), flat > 0.995 {
            XCTFail(
                "Snapshot \(name) rendered as a flat colour (\(String(format: "%.2f", flat * 100))% "
                    + "of pixels are one colour) — nothing was drawn, so this assertion is vacuous. "
                    + "ImageRenderer cannot draw ScrollView content; snapshot the scrollable content "
                    + "directly instead of the view that wraps it.",
                file: file,
                line: line
            )
            return
        }

        let snapshotURL = makeSnapshotURL(for: name, file: file)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        if isRecording {
            do {
                try actualData.write(to: snapshotURL)
                XCTFail("Recorded snapshot \(name). Re-run without SNAPSHOT_RECORD to validate.", file: file, line: line)
            } catch {
                XCTFail("Failed to record snapshot \(name): \(error)", file: file, line: line)
            }
            return
        }
        
        guard let baselineData = try? Data(contentsOf: snapshotURL) else {
            XCTFail("Missing baseline for \(name). Run with SNAPSHOT_RECORD=1 to create it.", file: file, line: line)
            return
        }
        
        if baselineData != actualData {
            if imagesMatchIgnoringEncoding(baselinePNGData: baselineData, actualPNGData: actualData) {
                return
            }

            if tolerance > 0,
               let differingFraction = differingPixelFraction(
                   baselinePNGData: baselineData,
                   actualPNGData: actualData
               ) {
                if differingFraction <= tolerance {
                    return
                }
                XCTFail(
                    "Snapshot mismatch for \(name): \(String(format: "%.3f", differingFraction * 100))% of "
                        + "pixels differ, tolerance is \(String(format: "%.3f", tolerance * 100))%.",
                    file: file,
                    line: line
                )
                return
            }

            let expectedAttachment = XCTAttachment(contentsOfFile: snapshotURL)
            expectedAttachment.name = "\(name)-baseline"
            expectedAttachment.lifetime = .deleteOnSuccess
            
            let actualAttachment = XCTAttachment(data: actualData, uniformTypeIdentifier: "public.png")
            actualAttachment.name = "\(name)-actual"
            actualAttachment.lifetime = .deleteOnSuccess
            
            add(expectedAttachment)
            add(actualAttachment)
            XCTFail("Snapshot mismatch for \(name).", file: file, line: line)
        }
    }
    
    private func makeSnapshotURL(for name: String, file: StaticString) -> URL {
        var url = URL(fileURLWithPath: String(describing: file))
        while url.lastPathComponent != "Tests" && url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        return url
            .appendingPathComponent(snapshotFolderName, isDirectory: true)
            .appendingPathComponent("\(name).png")
    }

    /// Fraction of pixels (0...1) occupied by the single most common colour.
    ///
    /// Used to detect a render that drew nothing. Samples every other pixel in
    /// each direction — a quarter of the work, and far more precision than the
    /// 0.995 threshold needs.
    private func dominantColorFraction(pngData: Data) -> Double? {
        guard let image = NSImage(data: pngData),
              let bytes = image.normalizedRGBABytes(),
              bytes.count % 4 == 0,
              !bytes.isEmpty else {
            return nil
        }
        let pixelCount = bytes.count / 4
        var counts: [UInt32: Int] = [:]
        var sampled = 0
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let px = raw.bindMemory(to: UInt8.self)
            for pixel in stride(from: 0, to: pixelCount, by: 2) {
                let offset = pixel * 4
                let key = UInt32(px[offset]) << 16 | UInt32(px[offset + 1]) << 8 | UInt32(px[offset + 2])
                counts[key, default: 0] += 1
                sampled += 1
            }
        }
        guard sampled > 0, let top = counts.values.max() else { return nil }
        return Double(top) / Double(sampled)
    }

    /// Fraction of pixels (0...1) whose RGBA bytes differ between the two images.
    /// Returns `nil` if either image cannot be decoded or the sizes differ — a
    /// size change is a real regression and must not be tolerated away.
    private func differingPixelFraction(baselinePNGData: Data, actualPNGData: Data) -> Double? {
        guard let baselineImage = NSImage(data: baselinePNGData),
              let actualImage = NSImage(data: actualPNGData),
              let baselineBytes = baselineImage.normalizedRGBABytes(),
              let actualBytes = actualImage.normalizedRGBABytes(),
              baselineBytes.count == actualBytes.count,
              baselineBytes.count % 4 == 0,
              !baselineBytes.isEmpty else {
            return nil
        }

        // Bind explicitly to UInt8 rather than subscripting the raw buffer.
        // `UnsafeRawBufferPointer`'s integer subscript is ambiguous on newer
        // Swift compilers ("ambiguous use of 'subscript(_:)'"), which compiled
        // fine locally and broke the CI runner's toolchain.
        let pixelCount = baselineBytes.count / 4
        var differingPixels = 0
        baselineBytes.withUnsafeBytes { (baselineRaw: UnsafeRawBufferPointer) in
            actualBytes.withUnsafeBytes { (actualRaw: UnsafeRawBufferPointer) in
                let baseline = baselineRaw.bindMemory(to: UInt8.self)
                let actual = actualRaw.bindMemory(to: UInt8.self)
                for pixel in 0..<pixelCount {
                    let offset = pixel * 4
                    if baseline[offset] != actual[offset]
                        || baseline[offset + 1] != actual[offset + 1]
                        || baseline[offset + 2] != actual[offset + 2]
                        || baseline[offset + 3] != actual[offset + 3] {
                        differingPixels += 1
                    }
                }
            }
        }
        return Double(differingPixels) / Double(pixelCount)
    }

    private func imagesMatchIgnoringEncoding(baselinePNGData: Data, actualPNGData: Data) -> Bool {
        guard let baselineImage = NSImage(data: baselinePNGData),
              let actualImage = NSImage(data: actualPNGData),
              let baselineBytes = baselineImage.normalizedRGBABytes(),
              let actualBytes = actualImage.normalizedRGBABytes() else {
            return false
        }
        return baselineBytes == actualBytes
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    func normalizedRGBABytes() -> Data? {
        var proposedRect = NSRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let byteCount = bytesPerRow * height

        var buffer = Data(count: byteCount)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        let result = buffer.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return result ? buffer : nil
    }
}
