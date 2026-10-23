import Accelerate
import CoreGraphics
import Foundation
import Vision

/// The quality pill's three readings (02 Flow B step 2, 03 §3.5).
public enum PageQuality: String, Sendable, Codable, CaseIterable {
    case sharp
    /// Motion or focus blur: the text's edges are soft.
    case holdStill
    /// A smudge or haze on the lens.
    case cleanTheLens

    /// The pill's words.
    public var label: String {
        switch self {
        case .sharp: "Sharp"
        case .holdStill: "Hold still"
        case .cleanTheLens: "Clean the lens"
        }
    }
}

/// The gate's reading of one image, with the measures behind it.
public struct PageQualityReading: Sendable, Equatable {
    public var quality: PageQuality
    /// Laplacian variance of the image's sharpest detail (the 90th percentile of its tiles), on a
    /// 0–255 gray scale at `PageQualityGate.measureLongSide` pixels.
    public var sharpness: Double
    /// Vision's lens-smudge confidence, 0…1.
    public var smudge: Double
    public var duration: Duration

    public init(quality: PageQuality, sharpness: Double, smudge: Double, duration: Duration = .zero) {
        self.quality = quality
        self.sharpness = sharpness
        self.smudge = smudge
        self.duration = duration
    }
}

/// Judges a captured page before it is read (01 §2.3): Vision's `DetectLensSmudgeRequest` for a
/// dirty lens, a Laplacian-variance sharpness measure for blur. Sharpness is taken over tiles and
/// the sharpest tenth counts, so a page with a soft photo or wide margins still reads Sharp when
/// its text is crisp, and a page blurred all over does not. Thresholds were tuned on the private
/// page fixtures (Phase 2 slice 2); the smudge threshold was set from the iPhone's scores on them
/// (slice 8, ux-notes row 171): the phone and the Mac score a hazy page up to 0.2 apart, and
/// 0.92 is where they disagree least (one photo of 91), the pages that read cleanly below it.
public struct PageQualityGate: Sendable {
    /// Below this the page reads Hold still.
    public var minimumSharpness: Double
    /// At or above this smudge confidence the page reads Clean the lens (Apple's sample uses 0.9;
    /// 0.92 from the device's scores, ux-notes row 171).
    public var smudgeThreshold: Double

    public static let measureLongSide = 2400
    static let tileColumns = 12
    static let tileRows = 16

    public init(minimumSharpness: Double = 220, smudgeThreshold: Double = 0.92) {
        self.minimumSharpness = minimumSharpness
        self.smudgeThreshold = smudgeThreshold
    }

    /// The file at full size, scaled as `assess(_:)` scales any image: the smudge detector reads a
    /// copy scaled one way differently from one scaled another, so every caller takes one path.
    public func assess(contentsOf url: URL) async throws -> PageQualityReading {
        let image = try PageImage.load(contentsOf: url)
        return await assess(image)
    }

    public func assess(_ image: CGImage) async -> PageQualityReading {
        let clock = ContinuousClock()
        let start = clock.now
        // Both measures on the same copy, so the reading doesn't depend on the size handed in.
        let measured = max(image.width, image.height) > Self.measureLongSide ? (PageImage.scaled(image, longSide: Self.measureLongSide) ?? image) : image
        let sharpness = Self.sharpness(of: measured)
        let smudge = (try? await DetectLensSmudgeRequest().perform(on: measured).confidence).map(Double.init) ?? 0
        return PageQualityReading(quality: quality(sharpness: sharpness, smudge: smudge), sharpness: sharpness, smudge: smudge, duration: clock.now - start)
    }

    public func quality(sharpness: Double, smudge: Double) -> PageQuality {
        if smudge >= smudgeThreshold { return .cleanTheLens }
        if sharpness < minimumSharpness { return .holdStill }
        return .sharp
    }

    /// The 90th percentile of the tiles' Laplacian variance, over tiles with some contrast.
    static func sharpness(of image: CGImage) -> Double {
        guard let (gray, width, height) = PageImage.grayPixels(of: image, longSide: measureLongSide), width > 8, height > 8 else { return 0 }
        var source = gray.map(Float.init)
        var laplacian = [Float](repeating: 0, count: width * height)
        let kernel: [Float] = [0, 1, 0, 1, -4, 1, 0, 1, 0]
        source.withUnsafeMutableBufferPointer { sourcePointer in
            laplacian.withUnsafeMutableBufferPointer { outPointer in
                var input = vImage_Buffer(data: sourcePointer.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * MemoryLayout<Float>.stride)
                var output = vImage_Buffer(data: outPointer.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * MemoryLayout<Float>.stride)
                _ = vImageConvolve_PlanarF(&input, &output, nil, 0, 0, kernel, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
            }
        }
        let tileWidth = width / tileColumns, tileHeight = height / tileRows
        var variances: [Double] = []
        for row in 0..<tileRows {
            for column in 0..<tileColumns {
                var sum = 0.0, sumSquares = 0.0, graySum = 0.0, graySquares = 0.0
                var count = 0.0
                for y in (row * tileHeight + 1)..<((row + 1) * tileHeight - 1) {
                    let base = y * width
                    for x in (column * tileWidth + 1)..<((column + 1) * tileWidth - 1) {
                        let value = Double(laplacian[base + x])
                        sum += value
                        sumSquares += value * value
                        let tone = Double(gray[base + x])
                        graySum += tone
                        graySquares += tone * tone
                        count += 1
                    }
                }
                guard count > 0 else { continue }
                let toneSpread = (graySquares / count - pow(graySum / count, 2)).squareRoot()
                // Blank paper and flat background say nothing about focus.
                guard toneSpread > 12 else { continue }
                variances.append(sumSquares / count - pow(sum / count, 2))
            }
        }
        guard !variances.isEmpty else { return 0 }
        variances.sort()
        return variances[Int(Double(variances.count - 1) * 0.9)]
    }
}
