import CoreGraphics
import Foundation
import ImageIO

/// Loads a page photo for reading: a HEIC, JPEG or PNG file, oriented as its EXIF says, at full
/// size or downscaled.
public enum PageImage {
    public enum LoadError: Error, Equatable {
        case unreadable(String)
    }

    /// The image with its orientation applied. `maxPixelSize` caps the long side; nil keeps the
    /// file's full size (page text is small in a photo of an open book, so the reader wants it).
    public static func load(contentsOf url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw LoadError.unreadable(url.lastPathComponent)
        }
        let longSide: Int
        if let maxPixelSize {
            longSide = maxPixelSize
        } else {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 4096
            let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 4096
            longSide = max(width, height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LoadError.unreadable(url.lastPathComponent)
        }
        return image
    }

    /// A photo's bytes (a camera capture, before anything is written), oriented as its metadata
    /// says, at full size or downscaled.
    public static func load(data: Data, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw LoadError.unreadable("capture") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let longSide = maxPixelSize ?? max(properties?[kCGImagePropertyPixelWidth] as? Int ?? 4096, properties?[kCGImagePropertyPixelHeight] as? Int ?? 4096)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw LoadError.unreadable("capture") }
        return image
    }

    /// `image` scaled so its long side is `longSide`.
    static func scaled(_ image: CGImage, longSide: Int) -> CGImage? {
        let scale = Double(longSide) / Double(max(image.width, image.height))
        let width = max(1, Int((Double(image.width) * scale).rounded())), height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// `image` scaled so its long side is at most `longSide`, drawn into 8-bit RGBA. The pixels come
    /// back with the size; row 0 is the top of the image.
    static func rgbaPixels(of image: CGImage, longSide: Int) -> (pixels: [UInt8], width: Int, height: Int)? {
        let scale = min(1, Double(longSide) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (pixels, width, height) : nil
    }

    /// `image` scaled so its long side is at most `longSide`, as 8-bit gray, row 0 at the top.
    static func grayPixels(of image: CGImage, longSide: Int) -> (pixels: [UInt8], width: Int, height: Int)? {
        let scale = min(1, Double(longSide) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (pixels, width, height) : nil
    }
}
