import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Testing
@testable import Capture

/// What the camera and Read Fixtures need from the pipeline (Phase 2 slice 4): cleaning a capture
/// (the page found, deskewed, cropped, levels and sharpening), reading a capture with the gate's
/// reading of the photo before cleanup, finishing a run read page by page, and the device report's
/// records. Made-up text only.
struct PageCaptureTests {
    // MARK: - Read Fixtures' report

    @Test func reportRoundTripsTheReadersScan() throws {
        let scan = PagePipelineTests.leekPage()
        let reading = PageStructurer().read(scan, file: "IMG_0001.HEIC")
        let quality = PageQualityReading(quality: .sharp, sharpness: 640, smudge: 0.2)
        let photo = DeviceReadingReport.Photo(fileName: "IMG_0001.HEIC", assetID: "ABC/L0/001",
                                              read: PagePipeline.PageRead(reading: reading, scan: scan, marginLines: nil, quality: quality), seconds: 1.4)
        // Whole seconds: the JSON keeps dates to the second.
        let report = DeviceReadingReport(createdAt: Date(timeIntervalSince1970: 1_792_000_000), device: "Test", build: "abc1234", readerMaxPixelSize: nil, photos: [photo])
        let decoded = try DeviceReadingReport.decoded(from: report.encoded())
        #expect(decoded == report)

        // The phone's blocks replayed on the Mac read as they did there.
        let stored = try #require(decoded.photos.first)
        let replayed = PageStructurer().read(PageScan(try #require(stored.scan)), file: stored.fileName)
        #expect(replayed.kind == reading.kind)
        #expect(replayed.recipes.map(\.title) == reading.recipes.map(\.title))
        #expect(replayed.recipes.map(\.ingredients.count) == reading.recipes.map(\.ingredients.count))
        #expect(replayed.recipes.map(\.steps.count) == reading.recipes.map(\.steps.count))
        #expect(replayed.pageNumber == reading.pageNumber)
        #expect(replayed.blocks.map(\.role) == reading.blocks.map(\.role))

        let result = try #require(stored.result)
        #expect(result.recipes.first?.ingredients == 5)
        #expect(result.recipes.first?.steps == 2)
        #expect(result.pageNumber == 34)
        #expect(result.roles.count == scan.blocks.count)
        #expect(stored.scan?.blocks.first?.lines.first?.text == "Braised Leeks with Mustard")
    }

    @Test func reportSummaryHoldsCountsOnly() {
        let scan = PagePipelineTests.leekPage()
        let reading = PageStructurer().read(scan, file: "IMG_0001.HEIC")
        let photo = DeviceReadingReport.Photo(fileName: "IMG_0001.HEIC", assetID: nil,
                                              read: PagePipeline.PageRead(reading: reading, scan: scan, marginLines: nil, quality: PageQualityReading(quality: .sharp, sharpness: 500, smudge: 0)), seconds: 2)
        var report = DeviceReadingReport(device: "Test", readerMaxPixelSize: 4_096, photos: [photo])
        report.photos.append(DeviceReadingReport.Photo(fileName: "IMG_0002.HEIC", seconds: 0.1, error: "unreadable"))
        let summary = report.summaryMarkdown
        #expect(summary.contains("| IMG_0001.HEIC | recipe | 0 |"))
        #expect(summary.contains("| IMG_0002.HEIC | unreadable |"))
        #expect(summary.contains("4096 px long side"))
        for text in ["Braised", "Leeks", "butter", "mustard", "Melt"] {
            #expect(!summary.contains(text), "the summary quotes the page: \(text)")
        }
    }

    // MARK: - The camera's reading

    /// A capture is measured before cleanup (sharpening would flatter a soft photo), and that
    /// reading travels with the cleaned page; a run read page by page finishes as the whole run would.
    @Test(.timeLimit(.minutes(3)))
    func readsACaptureWithTheGatesReadingOfTheOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "page-1.png")
        try Self.write(try PagePipelineTests.renderedPage(), to: url)

        let pipeline = PagePipeline()
        let measured = PageQualityReading(quality: .cleanTheLens, sharpness: 400, smudge: 0.95)
        let single = try await pipeline.readPage(contentsOf: url, page: 0, of: 1, quality: measured)
        #expect(single.quality.first??.quality == .cleanTheLens)
        #expect(single.quality.first??.smudge == 0.95)
        let finished = await pipeline.finish([single], urls: [url])
        let whole = try await pipeline.read(contentsOf: [url])
        #expect(finished.map(\.files) == whole.map(\.files))
        #expect(finished.map { $0.recipes.map(\.title) } == whole.map { $0.recipes.map(\.title) })
        #expect(finished.first?.recipes.first?.ingredients.count == 5)
    }

    // MARK: - Cleanup

    @Test func quadsTellAPageFromALabel() {
        let page = PageQuad(topLeft: PagePoint(x: 0.2, y: 0.1), topRight: PagePoint(x: 0.82, y: 0.14),
                            bottomRight: PagePoint(x: 0.78, y: 0.9), bottomLeft: PagePoint(x: 0.16, y: 0.86))
        #expect(page.isConvex)
        #expect(PageCleanup.isPlausible(page))
        #expect(abs(page.area() - 0.47) < 0.02)
        let label = PageQuad(topLeft: PagePoint(x: 0.4, y: 0.4), topRight: PagePoint(x: 0.6, y: 0.4),
                             bottomRight: PagePoint(x: 0.6, y: 0.5), bottomLeft: PagePoint(x: 0.4, y: 0.5))
        #expect(!PageCleanup.isPlausible(label))
        let crossed = PageQuad(topLeft: page.topLeft, topRight: page.bottomRight, bottomRight: page.topRight, bottomLeft: page.bottomLeft)
        #expect(!crossed.isConvex)
        // A page running out of the frame: the edge found is the frame's, so it isn't cropped to.
        let filling = PageQuad(topLeft: PagePoint(x: 0.007, y: 0.17), topRight: PagePoint(x: 0.993, y: 0.15),
                               bottomRight: PagePoint(x: 0.95, y: 0.9), bottomLeft: PagePoint(x: 0.05, y: 0.9))
        #expect(!PageCleanup.isPlausible(filling))
        // A trapezoid no tilt of the phone makes of a page.
        let skewed = PageQuad(topLeft: PagePoint(x: 0.1, y: 0.1), topRight: PagePoint(x: 0.9, y: 0.12),
                              bottomRight: PagePoint(x: 0.9, y: 0.95), bottomLeft: PagePoint(x: 0.1, y: 0.6))
        #expect(!PageCleanup.isPlausible(skewed))
        let expanded = page.expanded(by: 0.1)
        #expect(expanded.topLeft.x < page.topLeft.x && expanded.topLeft.y < page.topLeft.y)
        #expect(expanded.bottomRight.x > page.bottomRight.x && expanded.bottomRight.y > page.bottomRight.y)
        #expect(page.distance(to: page) == 0)
        #expect(abs(page.distance(to: expanded) - hypot(expanded.topLeft.x - page.topLeft.x, expanded.topLeft.y - page.topLeft.y)) < 0.05)
    }

    /// A page photographed at a slant on a dark table: found, flattened to its own shape, paper
    /// whitened and ink kept dark, and it reads as the page did.
    @Test(.timeLimit(.minutes(3)))
    func cleansAPhotographedPage() async throws {
        let page = try PagePipelineTests.renderedPage()
        let (photo, placed) = try Self.photographed(page)
        let found = try #require(await PageCleanup.detectPage(in: photo))
        #expect(found.distance(to: placed) < 0.04, "found \(found) for \(placed)")

        let cleaned = try #require(PageCleanup.clean(photo, page: found, enhances: true))
        // Flattened to the page's shape in the photo: its edges' mean lengths.
        func length(_ a: PagePoint, _ b: PagePoint) -> Double { hypot((a.x - b.x) * Double(photo.width), (a.y - b.y) * Double(photo.height)) }
        let expected = (length(placed.topLeft, placed.topRight) + length(placed.bottomLeft, placed.bottomRight))
            / (length(placed.topLeft, placed.bottomLeft) + length(placed.topRight, placed.bottomRight))
        let aspect = Double(cleaned.width) / Double(cleaned.height)
        #expect(abs(aspect - expected) < 0.05, "aspect \(aspect), expected \(expected)")
        // Paper is near white, ink near black; the table is gone.
        let (gray, width, height) = try #require(PageImage.grayPixels(of: cleaned, longSide: 600))
        let sorted = gray.sorted()
        #expect(sorted[sorted.count / 2] >= 235, "paper \(sorted[sorted.count / 2])")
        #expect(sorted[sorted.count / 200] <= 60, "ink \(sorted[sorted.count / 200])")
        let corner = gray[(height / 2) * width + 4]
        #expect(corner >= 200, "edge \(corner)")

        let reading = PageStructurer().read(try await PageReader().read(cleaned))
        #expect(reading.recipes.first?.title == "Lemon Barley Soup")
        #expect(reading.recipes.first?.ingredients.count == 5)
        #expect(reading.recipes.first?.steps.count == 2)

        // Photo mode: cropped the same, tones left alone.
        let plain = try #require(PageCleanup.clean(photo, page: found, enhances: false))
        #expect(plain.width == cleaned.width && plain.height == cleaned.height)
        let encoded = try #require(PageCleanup.encoded(cleaned))
        #expect(!encoded.data.isEmpty)
    }

    @Test func keepsTheWholeFrameWithoutAPage() throws {
        let page = try PagePipelineTests.renderedPage(width: 850, height: 1100)
        let cleaned = try #require(PageCleanup.clean(page, page: nil, enhances: true))
        #expect(cleaned.width == page.width && cleaned.height == page.height)
    }

    // MARK: - Helpers

    static func write(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// `page` laid on a dark table at a slant, as a camera would see it, with where it lies.
    static func photographed(_ page: CGImage) throws -> (CGImage, PageQuad) {
        let width = 3000.0, height = 2600.0
        let quad = PageQuad(topLeft: PagePoint(x: 0.27, y: 0.08), topRight: PagePoint(x: 0.74, y: 0.11),
                            bottomRight: PagePoint(x: 0.76, y: 0.93), bottomLeft: PagePoint(x: 0.24, y: 0.9))
        func vector(_ point: PagePoint) -> CGPoint { CGPoint(x: point.x * width, y: (1 - point.y) * height) }
        let transform = CIFilter.perspectiveTransform()
        transform.inputImage = CIImage(cgImage: page)
        transform.topLeft = vector(quad.topLeft)
        transform.topRight = vector(quad.topRight)
        transform.bottomRight = vector(quad.bottomRight)
        transform.bottomLeft = vector(quad.bottomLeft)
        let table = CIImage(color: CIColor(red: 0.22, green: 0.2, blue: 0.18)).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let composed = try #require(transform.outputImage).composited(over: table)
        let image = try #require(CIContext().createCGImage(composed, from: table.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)))
        return (image, quad)
    }
}
