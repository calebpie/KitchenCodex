import CoreGraphics
import Foundation
import Vision

/// Reads a cookbook's ISBN off a photo of its barcode (04 §5.1 "Add Cookbook": barcode first), with
/// Vision's barcode detector. Every barcode on a book since 2007 is the ISBN-13 as an EAN-13; other
/// EAN-13s (a price band, a product code) are not ISBNs and are passed over.
public enum ISBNBarcode {
    /// The ISBN-13 in the photo at `url`, or nil when no barcode in it reads as an ISBN. The photo is
    /// read at 3,000 pixels, then at full size when that finds nothing (a small barcode in a wide shot).
    public static func read(contentsOf url: URL) async throws -> String? {
        if let isbn = try await read(PageImage.load(contentsOf: url, maxPixelSize: 3_000)) { return isbn }
        return try await read(PageImage.load(contentsOf: url))
    }

    /// The ISBN-13 among the barcodes in `image`.
    public static func read(_ image: CGImage) async throws -> String? {
        var request = DetectBarcodesRequest()
        request.symbologies = [.ean13]
        let barcodes = try await request.perform(on: image)
        return barcodes.lazy.compactMap(\.payloadString).compactMap(ISBN.normalized).first
    }
}
