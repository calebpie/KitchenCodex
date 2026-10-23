import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// A point in unit image coordinates, top-left origin, as `PageRect`.
public struct PagePoint: Sendable, Equatable, Hashable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// The page's four corners in a photo, in unit image coordinates, top-left origin.
public struct PageQuad: Sendable, Equatable, Hashable, Codable {
    public var topLeft: PagePoint
    public var topRight: PagePoint
    public var bottomRight: PagePoint
    public var bottomLeft: PagePoint

    public init(topLeft: PagePoint, topRight: PagePoint, bottomRight: PagePoint, bottomLeft: PagePoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public var corners: [PagePoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// The share of the image it covers (the shoelace formula).
    public func area() -> Double {
        let points = corners
        var sum = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Whether the corners go round in order without crossing: every turn the same way.
    public var isConvex: Bool {
        let points = corners
        var sign = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % 4], c = points[(index + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            guard abs(cross) > 1e-6 else { return false }
            if sign == 0 { sign = cross } else if (sign > 0) != (cross > 0) { return false }
        }
        return true
    }

    /// The largest distance any corner moved from `other`'s, for telling a held page from a moving one.
    public func distance(to other: PageQuad) -> Double {
        zip(corners, other.corners).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
    }

    /// Whether `point` lies inside the quad (on an edge counts): on the same side of every edge.
    public func contains(_ point: PagePoint) -> Bool {
        let points = corners
        var sign = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % 4]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if abs(cross) < 1e-9 { continue }
            if sign == 0 { sign = cross } else if (sign > 0) != (cross > 0) { return false }
        }
        return true
    }

    /// Each corner pushed away from the centre by `fraction` of its distance, clamped to the image:
    /// a little room so a folio set close to the edge isn't trimmed.
    public func expanded(by fraction: Double) -> PageQuad {
        let cx = corners.map(\.x).reduce(0, +) / 4, cy = corners.map(\.y).reduce(0, +) / 4
        func push(_ point: PagePoint) -> PagePoint {
            PagePoint(x: min(1, max(0, cx + (point.x - cx) * (1 + fraction))), y: min(1, max(0, cy + (point.y - cy) * (1 + fraction))))
        }
        return PageQuad(topLeft: push(topLeft), topRight: push(topRight), bottomRight: push(bottomRight), bottomLeft: push(bottomLeft))
    }
}

/// A camera capture made ready to read (03 §3.5, phase2-plan slice 4 "Photo cleanup"): the page
/// found with Vision's document segmentation, deskewed and cropped to it with Core Image's
/// perspective correction, then levels set from the paper and the ink and the text sharpened. The
/// cleaned page is what the pipeline reads and what is stored as the page scan. A printed photo
/// captured in Photo mode is only deskewed and cropped: levels and sharpening are for print.
public enum PageCleanup {
    /// A page smaller than this share of the frame is more likely a printed photo or a label than
    /// the page; the whole frame is kept instead.
    public static let minimumPageArea = 0.15
    /// Room left around the detected edges, as a share of each corner's distance from the centre.
    public static let margin = 0.025
    /// Whether a Recipe capture gets levels and sharpening as well as the crop.
    public static let enhancesPages = true

    /// The page in `image`, upright as shown, or nil when Vision finds none worth cropping to.
    public static func detectPage(in image: CGImage) async -> PageQuad? {
        guard let observation = try? await DetectDocumentSegmentationRequest().perform(on: image) else { return nil }
        // Vision's points are unit coordinates from the bottom left.
        func point(_ normalized: NormalizedPoint) -> PagePoint { PagePoint(x: Double(normalized.x), y: 1 - Double(normalized.y)) }
        let quad = PageQuad(topLeft: point(observation.topLeft), topRight: point(observation.topRight),
                            bottomRight: point(observation.bottomRight), bottomLeft: point(observation.bottomLeft))
        return isPlausible(quad, aspect: Double(image.width) / Double(max(1, image.height))) ? quad : nil
    }

    /// The page's outline as Vision finds it in the frame the reader read (`quarterTurns`, as
    /// `PageScan` has them), with `isPlausible`'s tests but the edge clearance: a contents page's
    /// reader drops the lines outside it (ux-notes row 119) even where the page runs to the frame's
    /// edge and the outline is too doubtful to crop to.
    public static func detectOutline(in image: CGImage, quarterTurns: Int) async -> PageQuad? {
        let orientation: CGImagePropertyOrientation = switch quarterTurns % 4 {
        case 1: .left
        case 2: .down
        case 3: .right
        default: .up
        }
        guard let observation = try? await DetectDocumentSegmentationRequest().perform(on: image, orientation: orientation) else { return nil }
        func point(_ normalized: NormalizedPoint) -> PagePoint { PagePoint(x: Double(normalized.x), y: 1 - Double(normalized.y)) }
        let quad = PageQuad(topLeft: point(observation.topLeft), topRight: point(observation.topRight),
                            bottomRight: point(observation.bottomRight), bottomLeft: point(observation.bottomLeft))
        let turned = quarterTurns % 2 == 1
        let aspect = Double(turned ? image.height : image.width) / Double(max(1, turned ? image.width : image.height))
        return quad.isConvex && quad.area() >= minimumPageArea && hasPageShape(quad, aspect: aspect) ? quad : nil
    }

    /// Whether `quad` is a page to crop to: convex, a good share of the frame, clear of the frame's
    /// edges (a corner on the edge means the page runs out of the photo, and the edge found is the
    /// frame's), and shaped like a page seen at a modest angle (opposite sides of similar length).
    /// A page that fills the frame is read as it is.
    public static func isPlausible(_ quad: PageQuad, aspect: Double = 3 / 4) -> Bool {
        guard quad.isConvex, quad.area() >= minimumPageArea else { return false }
        guard quad.corners.allSatisfy({ $0.x > edgeClearance && $0.x < 1 - edgeClearance && $0.y > edgeClearance && $0.y < 1 - edgeClearance }) else { return false }
        return hasPageShape(quad, aspect: aspect)
    }

    /// Opposite sides of similar length, as a page seen at a modest angle has (`aspect` is the
    /// frame's width over its height).
    public static func hasPageShape(_ quad: PageQuad, aspect: Double) -> Bool {
        func length(_ a: PagePoint, _ b: PagePoint) -> Double { hypot((a.x - b.x) * aspect, a.y - b.y) }
        let top = length(quad.topLeft, quad.topRight), bottom = length(quad.bottomLeft, quad.bottomRight)
        let left = length(quad.topLeft, quad.bottomLeft), right = length(quad.topRight, quad.bottomRight)
        guard min(top, bottom, left, right) > 0 else { return false }
        return max(top, bottom) / min(top, bottom) <= maximumSideRatio && max(left, right) / min(left, right) <= maximumSideRatio
    }

    /// How far inside the frame every corner must be.
    public static let edgeClearance = 0.015
    /// The most two opposite sides may differ: about a 25° tilt of the phone.
    public static let maximumSideRatio = 1.3

    /// A cover candidate cropped to the page (ux-notes row 86): the outline whenever Vision finds a
    /// page-shaped one, with no edge-clearance test, then trimmed to the printed picture's bounds
    /// when the page holds one large picture (a plate bleeding to the page's edge keeps the page).
    /// Nil when nothing was found to crop to.
    public static func cropToPicture(_ image: CGImage) async -> CGImage? {
        var cropped = image
        if let quad = await detectOutline(in: image, quarterTurns: 0), let page = clean(image, page: quad, enhances: false, sharpens: false) {
            cropped = page
        } else if !(await detectOutline(in: image, quarterTurns: 0) == nil) {
            return nil
        }
        // The picture's bounds: the largest printed photo on the page, when it takes a good share.
        if let layout = PaperLayout.measure(cropped, quarterTurns: 0, text: []), let picture = layout.photos.max(by: { $0.area < $1.area }),
           picture.area >= 0.2, picture.area < 0.95 {
            let rect = CGRect(x: picture.minX * Double(cropped.width), y: picture.minY * Double(cropped.height),
                              width: picture.width * Double(cropped.width), height: picture.height * Double(cropped.height)).integral
            if let trimmed = cropped.cropping(to: rect) { return trimmed }
        }
        return cropped === image ? nil : cropped
    }

    /// `image` deskewed and cropped to `page` (the whole frame when nil), with levels and sharpening
    /// when `enhances`. Nil only when Core Image can't render it.
    public static func clean(_ image: CGImage, page: PageQuad?, enhances: Bool, sharpens: Bool = true, margin: Double = margin) -> CGImage? {
        var output = CIImage(cgImage: image)
        let width = Double(image.width), height = Double(image.height)
        if let page {
            let quad = page.expanded(by: margin)
            // Core Image's coordinates run from the bottom left, in pixels.
            func vector(_ point: PagePoint) -> CGPoint { CGPoint(x: point.x * width, y: (1 - point.y) * height) }
            let correction = CIFilter.perspectiveCorrection()
            correction.inputImage = output
            correction.topLeft = vector(quad.topLeft)
            correction.topRight = vector(quad.topRight)
            correction.bottomRight = vector(quad.bottomRight)
            correction.bottomLeft = vector(quad.bottomLeft)
            correction.crop = true
            if let corrected = correction.outputImage, corrected.extent.width >= 64, corrected.extent.height >= 64 {
                output = corrected.transformed(by: CGAffineTransform(translationX: -corrected.extent.minX, y: -corrected.extent.minY))
            }
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        if enhances {
            output = levels(output, context: context)
            if sharpens {
                let sharpen = CIFilter.sharpenLuminance()
                sharpen.inputImage = output
                sharpen.sharpness = 0.5
                sharpen.radius = 2
                output = sharpen.outputImage ?? output
            }
        }
        let extent = output.extent.integral
        return context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// Levels from the page itself: the ink's dark end (the 1st percentile of a small gray copy) to
    /// black and the paper (the 90th) to white, the same stretch on every channel, so colour type
    /// keeps its hue.
    static func levels(_ image: CIImage, context: CIContext) -> CIImage {
        let scale = 400 / max(image.extent.width, image.extent.height)
        let small = image.transformed(by: CGAffineTransform(scaleX: min(1, scale), y: min(1, scale)))
        guard let thumbnail = context.createCGImage(small, from: small.extent.integral),
              let (gray, _, _) = PageImage.grayPixels(of: thumbnail, longSide: 400), gray.count > 100 else { return image }
        let sorted = gray.sorted()
        let black = Double(sorted[sorted.count / 100]) / 255
        let white = Double(sorted[sorted.count * 9 / 10]) / 255
        // A page with little spread (a blank sheet, a photo plate) is left alone.
        guard white - black > 0.25 else { return image }
        // The filter works in linear light; the percentiles are gamma-encoded.
        let low = linear(black), high = linear(white)
        let gain = 1 / max(0.05, high - low)
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: -low * gain, y: -low * gain, z: -low * gain, w: 0)
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = matrix.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return clamp.outputImage ?? image
    }

    private static func linear(_ encoded: Double) -> Double {
        encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }

    /// The cleaned page as a file: HEIC where the system can encode it, else JPEG.
    public static func encoded(_ image: CGImage, quality: Double = 0.9) -> (data: Data, fileExtension: String)? {
        for (type, fileExtension) in [(UTType.heic, "heic"), (UTType.jpeg, "jpg")] {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), data.length > 0 { return (data as Data, fileExtension) }
        }
        return nil
    }
}
