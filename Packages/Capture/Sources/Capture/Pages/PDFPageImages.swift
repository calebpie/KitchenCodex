import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A PDF's pages as images, so a scanned or exported cookbook PDF goes through the page pipeline
/// as photographs do (phase2-plan "Slice 8": PDF import through the same pipeline). Each page is
/// drawn on white at `maxPixelSize` on its long side, about the camera's 4,000 pixels by default,
/// and written as a JPEG beside the others.
public enum PDFPageImages {
    public static let defaultLongSide = 4_000

    /// Whether the file is a PDF, by its extension or its type.
    public static func isPDF(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" { return true }
        return (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .pdf)) == true
    }

    /// The number of pages, or 0 when the file isn't a PDF that opens.
    public static func pageCount(of url: URL) -> Int {
        CGPDFDocument(url as CFURL)?.numberOfPages ?? 0
    }

    /// Every page of `url` rendered into `folder` as `page-N.jpg`, in page order. An empty array
    /// when the file doesn't open.
    public static func render(_ url: URL, into folder: URL, maxPixelSize: Int = defaultLongSide, prefix: String = "page") -> [URL] {
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else { return [] }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [URL] = []
        for number in 1...document.numberOfPages {
            guard let page = document.page(at: number), let image = render(page, maxPixelSize: maxPixelSize) else { continue }
            let destination = folder.appending(path: "\(prefix)-\(number).jpg")
            guard let sink = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(sink, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
            if CGImageDestinationFinalize(sink) { written.append(destination) }
        }
        return written
    }

    /// One page drawn upright on white, its rotation applied.
    public static func render(_ page: CGPDFPage, maxPixelSize: Int = defaultLongSide) -> CGImage? {
        let box = page.getBoxRect(.cropBox)
        let rotation = ((page.rotationAngle % 360) + 360) % 360
        let turned = rotation == 90 || rotation == 270
        let width = turned ? box.height : box.width, height = turned ? box.width : box.height
        guard width > 0, height > 0 else { return nil }
        let scale = Double(maxPixelSize) / Double(max(width, height))
        let pixelWidth = max(1, Int((width * scale).rounded())), pixelHeight = max(1, Int((height * scale).rounded()))
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }
}
