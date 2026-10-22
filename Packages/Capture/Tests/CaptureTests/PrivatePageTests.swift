import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Intelligence
import Testing
import Vision
@testable import Capture

/// The page pipeline over Caleb's private page photos (phase2-plan "Slice 2"): each book's barcode
/// read for its ISBN, then every other photo through the quality gate, the reader and the structurer,
/// consecutive pages stitched, review simulated per book as the cook would meet it, a private report
/// written to `Docs/Fixtures/Private/Review/page-review-2026-10-20.md`, and the readings checked
/// against `Fixtures/private-pages.json` (counts only). Deterministic unless
/// `RECIPE_CODEX_PAGE_MODEL=1`, which adds the on-device model's pass. Skipped where the photos are
/// absent (CI, cloud sessions).
@Suite("Page pipeline, private page photos", .enabled(if: PageFixtures.available, PageFixtures.skipReason), .serialized)
struct PrivatePageTests {
    static let reportName = "page-review-2026-10-20.md"
    static let usesModel = ProcessInfo.processInfo.environment["RECIPE_CODEX_PAGE_MODEL"] == "1"

    @Test(.timeLimit(.minutes(20)))
    func readsEveryPhotographedPage() async throws {
        // Books the manifest doesn't list yet are skipped and named in the report; the listed
        // ones keep every check.
        let all = PageFixtures.books()
        let books = all.filter(PageFixtures.isInManifest)
        #expect(!books.isEmpty)
        let manifest = Dictionary(PageFixtures.manifest.map { ("\($0.slug)/\($0.file)", $0) }, uniquingKeysWith: { first, _ in first })
        let pipeline = PagePipeline()
        var report = PageReport(usesModel: Self.usesModel)
        report.unlisted = all.filter { !PageFixtures.isInManifest($0) }.map { ($0.slug, $0.files.count) }
        let hint = "If the reading improved, update Fixtures/private-pages.json (counts only)."

        for book in books {
            var bookReport = PageReport.Book(slug: book.slug, photos: book.files.count)
            guard let barcodeFile = book.files.first else { continue }

            // The barcode photo: the book's ISBN.
            let isbn = try await Self.isbn(in: barcodeFile)
            bookReport.isbn = isbn
            let barcodeEntry = manifest["\(book.slug)/\(barcodeFile.lastPathComponent)"]
            #expect(barcodeEntry != nil, "Add \(book.slug)/\(barcodeFile.lastPathComponent) to the manifest")
            if let expected = barcodeEntry?.isbn {
                #expect(isbn == expected, "\(book.slug): barcode read \(isbn ?? "nothing"), manifest says \(expected)")
            }

            // Every other photo: gate, read, structure.
            var readings: [PageReading] = []
            for file in book.files.dropFirst() {
                let reading = try await pipeline.read(contentsOf: file)
                readings.append(reading)
            }
            let stitched = PageStitcher.stitch(readings)

            // Review as the cook would meet it: the book's first recipe and each new layout are
            // forced, and confirming a review adds its layout to the book's confirmed ones.
            var reviewedLayouts = Set<String>()
            var hasRecipes = false
            var reviews: [String: [[ReviewReason]]] = [:]
            for reading in stitched where reading.kind == .recipe {
                var perRecipe: [[ReviewReason]] = []
                for recipe in reading.recipes {
                    let reasons = recipe.reviewReasons(bookHasRecipes: hasRecipes, reviewedLayouts: reviewedLayouts)
                    perRecipe.append(reasons)
                    if !reasons.isEmpty { reviewedLayouts.insert(recipe.layoutSignature) }
                    hasRecipes = true
                }
                reviews[reading.files[0]] = perRecipe
            }

            // The model's pass, only when asked.
            var modelNotes: [String] = []
            if Self.usesModel {
                modelNotes = await Self.modelPass(on: stitched, book: book)
            }

            // Check against the manifest.
            for file in book.files.dropFirst() {
                let name = file.lastPathComponent
                guard let entry = manifest["\(book.slug)/\(name)"] else {
                    Issue.record("Add \(book.slug)/\(name) to Fixtures/private-pages.json")
                    continue
                }
                guard let single = readings.first(where: { $0.files == [name] }) else { continue }
                let gate = single.quality.first??.quality.rawValue
                #expect(gate == entry.gate, "\(entry.testDescription): gate \(gate ?? "-"), manifest \(entry.gate)")
                if let page = entry.page {
                    #expect(single.pageNumber == page, "\(entry.testDescription): page \(single.pageNumber.map(String.init) ?? "none"), manifest \(page) \(hint)")
                }
                let reading = stitched.first { $0.files.contains(name) }
                switch entry.kind {
                case "recipe", "spread-start":
                    #expect(single.kind == .recipe && !single.isContinuation, "\(entry.testDescription): read as \(single.kind.rawValue)\(single.isContinuation ? ", a continuation" : "") \(hint)")
                    if entry.kind == "spread-start" {
                        #expect((reading?.files.count ?? 0) > 1, "\(entry.testDescription): not stitched to the next page \(hint)")
                    }
                    if let expected = entry.recipes, let reading, reading.files.first == name {
                        let counts = reading.recipes.map { PageFixtures.RecipeCounts(ingredients: $0.ingredients.count, steps: $0.steps.count) }
                        #expect(counts == expected, "\(entry.testDescription): read \(counts.map { "\($0.ingredients)/\($0.steps)" }), manifest \(expected.map { "\($0.ingredients)/\($0.steps)" }) \(hint)")
                    }
                case "spread-middle", "spread-end":
                    #expect(single.isContinuation, "\(entry.testDescription): should continue the page before \(hint)")
                    #expect(reading?.files.first != name, "\(entry.testDescription): not stitched to the page before \(hint)")
                case "reference", "glossary":
                    #expect(single.kind == .prose && single.reference != nil, "\(entry.testDescription): read as \(single.kind.rawValue), no reference \(hint)")
                    if entry.kind == "glossary" {
                        #expect(single.reference?.kind == .glossary, "\(entry.testDescription): read as \(single.reference?.kind.rawValue ?? "nothing"), not a glossary \(hint)")
                    }
                    if let expected = entry.sections {
                        #expect(single.reference?.sections.count == expected, "\(entry.testDescription): \(single.reference?.sections.count ?? 0) sections, manifest \(expected) \(hint)")
                    }
                case "contents", "index", "sources", "photo":
                    #expect(single.kind.rawValue == entry.kind, "\(entry.testDescription): read as \(single.kind.rawValue) \(hint)")
                    if let expected = entry.suppliers {
                        let count = SourcesPageReader.read(single).count
                        #expect(count == expected, "\(entry.testDescription): \(count) suppliers, manifest \(expected) \(hint)")
                    }
                    if let expected = entry.contents {
                        let contents = ContentsReader.read(single)
                        let counts = PageFixtures.ContentsCounts(sections: contents.sections.count, entries: contents.entries.count, paged: contents.pagedEntryCount)
                        #expect(counts == expected, "\(entry.testDescription): contents read \(counts.sections)/\(counts.entries)/\(counts.paged) (sections/entries/paged), manifest \(expected.sections)/\(expected.entries)/\(expected.paged) \(hint)")
                    }
                case "bad-capture":
                    #expect(gate != PageQuality.sharp.rawValue, "\(entry.testDescription): a bad capture read Sharp")
                default:
                    break
                }
            }

            // The punchlist the contents pages build, contents before index (02 Flow C step 3).
            let contentsPages = readings.filter { $0.kind == .contents }.map(ContentsReader.read)
            let indexPages = readings.filter { $0.kind == .index }.map(ContentsReader.read)
            if !contentsPages.isEmpty || !indexPages.isEmpty {
                bookReport.contents = ContentsReader.combine(contentsPages, indexPages: indexPages)
            }
            bookReport.readings = stitched
            bookReport.singles = readings
            bookReport.reviews = reviews
            bookReport.modelNotes = modelNotes
            report.books.append(bookReport)
        }

        // The gate on deliberately bad captures, made in memory from good pages (the photos hold no
        // blurred or smeared capture): blurred copies must not read Sharp.
        report.blurred = try await Self.blurredCaptures(books: books)
        for check in report.blurred {
            #expect(check.reading.quality != .sharp, "\(check.label) read Sharp (sharpness \(Int(check.reading.sharpness)))")
        }

        try report.write(to: PageFixtures.reviewDirectory!.appending(path: Self.reportName))
    }

    @Test func everyPhotoHasAManifestEntry() {
        let recorded = Set(PageFixtures.manifest.map { "\($0.slug)/\($0.file)" })
        let missing = PageFixtures.books().filter(PageFixtures.isInManifest).flatMap { book in book.files.map { "\(book.slug)/\($0.lastPathComponent)" } }.filter { !recorded.contains($0) }
        #expect(missing.isEmpty, "Add these photos to Fixtures/private-pages.json: \(missing)")
    }

    // MARK: - Barcodes

    /// The ISBN-13 on the barcode photo, as Add Cookbook reads it.
    static func isbn(in url: URL) async throws -> String? {
        try await ISBNBarcode.read(contentsOf: url)
    }

    // MARK: - Bad captures

    struct BlurCheck {
        var label: String
        var reading: PageQualityReading
    }

    /// Each book's first page and a page from its middle, blurred as a shaky hand (motion) and an
    /// unfocused lens (Gaussian) would.
    static func blurredCaptures(books: [PageFixtures.Book]) async throws -> [BlurCheck] {
        let gate = PageQualityGate()
        let context = CIContext()
        var checks: [BlurCheck] = []
        for book in books where book.files.count > 2 {
            for file in [book.files[1], book.files[book.files.count / 2]] {
                let image = try PageImage.load(contentsOf: file, maxPixelSize: 4000)
                for (name, filterName, radius) in [("motion blur, 12 px", "CIMotionBlur", 12.0), ("out of focus, 3 px", "CIGaussianBlur", 3.0)] {
                    let source = CIImage(cgImage: image)
                    guard let filter = CIFilter(name: filterName) else { continue }
                    filter.setValue(source, forKey: kCIInputImageKey)
                    filter.setValue(radius, forKey: kCIInputRadiusKey)
                    guard let output = filter.outputImage?.cropped(to: source.extent),
                          let blurred = context.createCGImage(output, from: source.extent) else { continue }
                    let reading = await gate.assess(blurred)
                    checks.append(BlurCheck(label: "\(book.slug)/\(file.lastPathComponent), \(name)", reading: reading))
                }
            }
        }
        return checks
    }

    // MARK: - The model

    /// The model on recipes the deterministic reading left short, and, for comparison, on each book's
    /// first recipe page: what it read and how long it took. Nothing here is asserted.
    static func modelPass(on readings: [PageReading], book: PageFixtures.Book) async -> [String] {
        let model = OnDevicePageStructurer()
        guard model.isAvailable else { return ["The on-device model is not available on this host."] }
        var notes: [String] = []
        let pipeline = PagePipeline(model: model)
        let clock = ContinuousClock()
        for reading in readings where reading.kind == .recipe && reading.recipes.contains(where: PagePipeline.wantsModel) {
            let image = book.files.first { $0.lastPathComponent == reading.files[0] }.flatMap { try? PageImage.load(contentsOf: $0, maxPixelSize: 1600) }
            let start = clock.now
            let refined = await pipeline.refine(reading, image: image)
            let seconds = (clock.now - start).seconds
            for recipe in refined.recipes {
                notes.append("\(reading.files.joined(separator: " + ")): model pass \(recipe.method == .model ? "used" : "not used"), \(recipe.ingredients.count) ingredients, \(recipe.steps.count) steps, \(String(format: "%.1f", seconds)) s")
            }
        }
        if let first = readings.first(where: { $0.kind == .recipe && !$0.isContinuation }), let recipe = first.recipes.first {
            let text = PagePipeline.text(of: recipe, in: first)
            let start = clock.now
            if let draft = try? await model.structure(pageText: text) {
                let seconds = (clock.now - start).seconds
                notes.append("Comparison on \(first.files[0]) (text only): the model read \(draft.ingredients.count) ingredients and \(draft.steps.count) steps in \(String(format: "%.1f", seconds)) s; the deterministic reading has \(recipe.ingredients.count) and \(recipe.steps.count).")
            } else {
                notes.append("Comparison on \(first.files[0]): the model's text pass failed.")
            }
            if model.acceptsImages, let file = book.files.first(where: { $0.lastPathComponent == first.files[0] }),
               let image = try? PageImage.load(contentsOf: file, maxPixelSize: 1600) {
                let imageStart = clock.now
                if let draft = try? await model.structure(pageText: text, image: image) {
                    let seconds = (clock.now - imageStart).seconds
                    notes.append("Comparison on \(first.files[0]) (photo and text): \(draft.ingredients.count) ingredients and \(draft.steps.count) steps in \(String(format: "%.1f", seconds)) s.")
                } else {
                    notes.append("Comparison on \(first.files[0]) (photo and text): the image pass failed.")
                }
            }
        }
        return notes
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

/// Runs everywhere, including checkouts without the photos: the committed manifest holds slugs,
/// ISBNs, file names, kinds, gate readings, page numbers and counts, and nothing from the books.
@Suite("Page manifest")
struct PageManifestTests {
    @Test func manifestHoldsNoPageText() throws {
        let url = try #require(Bundle.module.url(forResource: PageFixtures.manifestName, withExtension: "json", subdirectory: "Fixtures"))
        let entries = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        #expect(!entries.isEmpty)
        #expect(PageFixtures.manifest.count == entries.count, "every entry decodes")
        let allowed: Set<String> = ["slug", "isbn", "file", "kind", "gate", "page", "recipes", "contents", "sections", "suppliers", "settled", "note"]
        let kinds: Set<String> = ["recipe", "spread-start", "spread-middle", "spread-end", "contents", "index", "sources", "photo", "reference", "glossary", "bad-capture", "other"]
        let gates = Set(PageQuality.allCases.map(\.rawValue))
        for entry in entries {
            #expect(Set(entry.keys).isSubset(of: allowed), "\(entry.keys.sorted())")
        }
        for entry in PageFixtures.manifest {
            #expect(entry.slug.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil)
            #expect(entry.isbn.range(of: #"^97[89]\d{10}$"#, options: .regularExpression) != nil)
            #expect(entry.file.range(of: #"^[A-Za-z0-9_-]+\.(HEIC|heic|JPG|jpg|jpeg|png)$"#, options: .regularExpression) != nil)
            #expect(kinds.contains(entry.kind))
            #expect(gates.contains(entry.gate))
            #expect(entry.contents == nil || entry.kind == "contents" || entry.kind == "index", "contents counts belong to contents and index pages")
            #expect(entry.sections == nil || entry.kind == "reference" || entry.kind == "glossary", "section counts belong to reference and glossary pages")
            #expect(entry.suppliers == nil || entry.kind == "sources", "supplier counts belong to Sources pages")
            // A note describes the capture ("ISBN barcode", "haze over the upper left"), never the page's words.
            #expect((entry.note?.count ?? 0) <= 160)
        }
    }
}
