import CoreGraphics
import CoreML
import Foundation
import Vision

/// Reads a cookbook's ISBN off a photo of its barcode (04 §5.1 "Add Cookbook": barcode first), with
/// Vision's barcode detector. Every barcode on a book since 2007 is the ISBN-13 as an EAN-13; other
/// EAN-13s (a price band, a product code) are not ISBNs and are passed over.
public enum ISBNBarcode {
    /// The ISBN-13 in the photo at `url`, or nil when no barcode in it reads as an ISBN. The photo is
    /// read at 3,000 pixels, then at full size when that finds nothing (a small barcode in a wide
    /// shot), then by Vision's second revision at smaller sizes where the current detector can't
    /// run (the iOS Simulator).
    public static func read(contentsOf url: URL) async throws -> String? {
        if let isbn = try await read(PageImage.load(contentsOf: url, maxPixelSize: 3_000)) { return isbn }
        if let isbn = try await read(PageImage.load(contentsOf: url)) { return isbn }
        for size in [1_200, 2_000] {
            if let isbn = try secondRevision(PageImage.load(contentsOf: url, maxPixelSize: size)) { return isbn }
        }
        return nil
    }

    /// The ISBN-13 among the barcodes in `image`. Where the current detector can't be created or
    /// reads nothing (the iOS Simulator: "Failed to create barcode detector", and nothing on the
    /// CPU), Vision's second revision, pinned to the CPU, which reads EAN-13 there, has a go.
    public static func read(_ image: CGImage) async throws -> String? {
        var request = DetectBarcodesRequest()
        request.symbologies = [.ean13]
        let barcodes = (try? await request.perform(on: image)) ?? []
        if let isbn = barcodes.lazy.compactMap(\.payloadString).compactMap(ISBN.normalized).first { return isbn }
        return try secondRevision(image)
    }

    private static func secondRevision(_ image: CGImage) throws -> String? {
        let request = VNDetectBarcodesRequest()
        let revision = 2
        guard VNDetectBarcodesRequest.supportedRevisions.contains(revision) else { return nil }
        request.revision = revision
        request.symbologies = [.ean13]
        if let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { true } else { false } }) {
            for stage in try request.supportedComputeStageDevices.keys { request.setComputeDevice(cpu, for: stage) }
        }
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).lazy.compactMap(\.payloadStringValue).compactMap(ISBN.normalized).first
    }
}
