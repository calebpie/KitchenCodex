import Foundation

/// Read Fixtures' report (04 §5.1 "Device readings", ux-notes row 63): what the reader saw on each
/// fixture photo on a device and what the structurer made of it, so the harness can replay the
/// phone's blocks on the Mac (`DeviceReplay`, slice 8) and compare. The JSON holds the page text
/// and stays on the device and in `Docs/Fixtures/Private`; `summaryMarkdown` holds counts only.
/// Format 2 (slice 8) adds the page's outline, the margin lines on every recipe and prose page, the
/// skew measure, and the reference, contents and Sources readings' counts; a format 1 report
/// decodes with those absent.
public struct DeviceReadingReport: Codable, Sendable, Equatable {
    public var formatVersion = 2
    public var createdAt: Date
    /// "iPhone18,1 · iOS 27.0", what read the photos.
    public var device: String
    /// The app's build ("8dba44e · 2026-10-20T…Z"), when known.
    public var build: String?
    /// The long side photos were read at; nil for full size.
    public var readerMaxPixelSize: Int?
    public var photos: [Photo]

    public init(createdAt: Date = .now, device: String, build: String? = nil, readerMaxPixelSize: Int?, photos: [Photo] = []) {
        self.createdAt = createdAt
        self.device = device
        self.build = build
        self.readerMaxPixelSize = readerMaxPixelSize
        self.photos = photos
    }

    /// One photo's reading.
    public struct Photo: Codable, Sendable, Equatable {
        /// The photo's file name, as Photos or Files gave it.
        public var fileName: String
        /// The Photos asset's identifier, when it came from Photos.
        public var assetID: String?
        public var quality: Quality?
        /// What the reader saw, enough to rebuild its `PageScan`.
        public var scan: Scan?
        /// The page's foot and head read again (every recipe and prose page from format 2; before
        /// that, only when no folio was found).
        public var marginLines: [String]?
        /// The page's outline as the device found it for a contents or index page (format 2), in
        /// the frame the blocks are in.
        public var outline: PageQuad?
        public var result: Result?
        public var seconds: Double
        /// Why the photo couldn't be read.
        public var error: String?

        public init(fileName: String, assetID: String? = nil, quality: Quality? = nil, scan: Scan? = nil, marginLines: [String]? = nil, outline: PageQuad? = nil, result: Result? = nil, seconds: Double = 0, error: String? = nil) {
            self.fileName = fileName
            self.assetID = assetID
            self.quality = quality
            self.scan = scan
            self.marginLines = marginLines
            self.outline = outline
            self.result = result
            self.seconds = seconds
            self.error = error
        }
    }

    public struct Quality: Codable, Sendable, Equatable {
        public var quality: PageQuality
        public var sharpness: Double
        public var smudge: Double
    }

    /// The reader's output (`PageScan`).
    public struct Scan: Codable, Sendable, Equatable {
        public var pixelWidth: Int
        public var pixelHeight: Int
        public var quarterTurns: Int
        public var paper: PageRect?
        public var pageCore: PageRect?
        public var paperFraction: Double
        /// The text lines' median tilt in degrees clockwise (format 2; ux-notes row 133).
        public var skewDegrees: Double?
        /// Lines set aside as read in another script (format 2; ux-notes row 126).
        public var nonLatinLines: Int?
        public var blocks: [Block]
    }

    /// One block as the reader made it: its kind, unit rect, lines, confidence and type size, and
    /// the role the reader itself gave (`ignore` for text off the page).
    public struct Block: Codable, Sendable, Equatable {
        public var id: Int
        public var kind: PageBlock.Kind
        public var readerRole: PageBlock.Role?
        public var rect: PageRect
        public var marker: String?
        public var confidence: Double
        public var typeSize: Double
        public var lines: [Line]
    }

    public struct Line: Codable, Sendable, Equatable {
        public var text: String
        public var rect: PageRect
        public var confidence: Double
        public var size: Double
        public var top: Double
    }

    /// The structured result (`PageReading`).
    public struct Result: Codable, Sendable, Equatable {
        public var kind: PageKind
        public var reason: String?
        public var pageNumber: Int?
        public var quarterTurns: Int
        public var ocrConfidence: Double
        public var isContinuation: Bool
        /// The structurer's role for each block, and the recipe and item it fed.
        public var roles: [BlockRole]
        public var recipes: [Recipe]
        /// For a prose page that read as reference reading: its kind ("glossary", "chapter",
        /// "technique") and its sections (format 2; ux-notes row 107).
        public var referenceKind: String?
        public var referenceSections: Int?
        /// For a contents or index page: its chapters, entries and entries with a page as
        /// `ContentsReader` reads them, an index page's entries counted as its index (format 2).
        public var contents: ContentsCounts?
        /// For a Sources page: the suppliers read (format 2).
        public var suppliers: Int?
        /// The second language a title's alternate name read as, when one did (format 2).
        public var secondLanguage: String?
    }

    public struct ContentsCounts: Codable, Sendable, Equatable {
        public var sections: Int
        public var entries: Int
        public var paged: Int

        public init(sections: Int, entries: Int, paged: Int) {
            self.sections = sections
            self.entries = entries
            self.paged = paged
        }
    }

    public struct BlockRole: Codable, Sendable, Equatable {
        public var id: Int
        public var role: PageBlock.Role?
        public var recipe: Int?
        public var item: Int?
    }

    public struct Recipe: Codable, Sendable, Equatable {
        public var title: String
        public var yield: String?
        public var hasHeadnote: Bool
        public var ingredients: Int
        public var unparsedIngredients: Int
        public var groups: Int
        public var steps: Int
        public var notes: Int
        public var crossReferences: Int
        public var layoutSignature: String
        public var ocrConfidence: Double
        public var parserConfidence: Double
        public var structureConfidence: Double
        public var combinedConfidence: Double
        /// The reasons review would ask, for a book with recipes and no confirmed layout.
        public var reviewReasons: [ReviewReason]
        public var stepCountDisagrees: Bool
        public var unassignedBlocks: [Int]
    }
}

extension DeviceReadingReport.Photo {
    /// A photo's record from what the pipeline read (`PagePipeline.readForReport`).
    public init(fileName: String, assetID: String?, read: PagePipeline.PageRead, seconds: Double) {
        let scan = read.scan
        let reading = read.reading
        var contents: DeviceReadingReport.ContentsCounts?
        if reading.kind == .contents || reading.kind == .index {
            let read = ContentsReader.read(reading)
            let listed = reading.kind == .index ? read.index : read.entries
            contents = DeviceReadingReport.ContentsCounts(sections: read.sections.count, entries: listed.count, paged: listed.count { $0.page != nil })
        }
        self.init(
            fileName: fileName, assetID: assetID,
            quality: DeviceReadingReport.Quality(quality: read.quality.quality, sharpness: read.quality.sharpness, smudge: read.quality.smudge),
            scan: DeviceReadingReport.Scan(
                pixelWidth: scan.pixelWidth, pixelHeight: scan.pixelHeight, quarterTurns: scan.quarterTurns,
                paper: scan.paper, pageCore: scan.pageCore, paperFraction: scan.paperFraction,
                skewDegrees: scan.skewDegrees, nonLatinLines: scan.nonLatinLines,
                blocks: scan.blocks.map { block in
                    DeviceReadingReport.Block(
                        id: block.id, kind: block.kind, readerRole: block.role, rect: block.rect, marker: block.marker,
                        confidence: block.confidence, typeSize: block.typeSize,
                        lines: block.lines.map { DeviceReadingReport.Line(text: $0.text, rect: $0.rect, confidence: $0.confidence, size: $0.size, top: $0.top) }
                    )
                }
            ),
            marginLines: read.marginLines,
            outline: reading.outline,
            result: DeviceReadingReport.Result(
                kind: reading.kind, reason: reading.reason, pageNumber: reading.pageNumber,
                quarterTurns: reading.quarterTurns.first ?? scan.quarterTurns, ocrConfidence: reading.ocrConfidence,
                isContinuation: reading.isContinuation,
                roles: reading.blocks.map { DeviceReadingReport.BlockRole(id: $0.id, role: $0.role, recipe: $0.recipe, item: $0.item) },
                recipes: reading.recipes.map { recipe in
                    DeviceReadingReport.Recipe(
                        title: recipe.title, yield: recipe.yield, hasHeadnote: recipe.headnote != nil,
                        ingredients: recipe.ingredients.count, unparsedIngredients: recipe.unparsedIngredientCount,
                        groups: Set(recipe.ingredients.compactMap(\.group)).count, steps: recipe.steps.count,
                        notes: recipe.notes.count, crossReferences: recipe.crossReferences.count,
                        layoutSignature: recipe.layoutSignature,
                        ocrConfidence: recipe.confidence.ocr, parserConfidence: recipe.confidence.parser,
                        structureConfidence: recipe.confidence.structure, combinedConfidence: recipe.confidence.combined,
                        reviewReasons: recipe.reviewReasons(bookHasRecipes: true, reviewedLayouts: []),
                        stepCountDisagrees: recipe.stepCountDisagrees, unassignedBlocks: recipe.unassignedBlocks
                    )
                },
                referenceKind: reading.reference?.kind.rawValue,
                referenceSections: reading.reference.map { $0.sections.count },
                contents: contents,
                suppliers: reading.kind == .sources ? SourcesPageReader.read(reading).count : nil,
                secondLanguage: reading.secondLanguage
            ),
            seconds: seconds
        )
    }
}

extension PageScan {
    /// The reader's scan rebuilt from a report, for replaying a device's reading through the
    /// structurer on the Mac.
    public init(_ record: DeviceReadingReport.Scan) {
        let blocks = record.blocks.map { stored -> PageBlock in
            var block = PageBlock(
                id: stored.id, kind: stored.kind, rect: stored.rect,
                lines: stored.lines.map { PageTextLine(text: $0.text, rect: $0.rect, confidence: $0.confidence, size: $0.size, top: $0.top) },
                marker: stored.marker
            )
            block.role = stored.readerRole
            return block
        }
        self.init(blocks: blocks, pixelWidth: record.pixelWidth, pixelHeight: record.pixelHeight, quarterTurns: record.quarterTurns, paper: record.paper)
        paperFraction = record.paperFraction
        pageCore = record.pageCore
        skewDegrees = record.skewDegrees ?? 0
        nonLatinLines = record.nonLatinLines ?? 0
    }
}

extension DeviceReadingReport {
    /// The report as JSON, dates in ISO 8601, keys sorted so two reports diff cleanly.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> DeviceReadingReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DeviceReadingReport.self, from: data)
    }

    /// The Markdown summary: counts only, no page text, so it can be read anywhere.
    public var summaryMarkdown: String {
        var lines = [
            "# Read Fixtures report",
            "",
            "- Read: \(createdAt.formatted(.iso8601))",
            "- Device: \(device)",
            "- Build: \(build ?? "unknown")",
            "- Read at: \(readerMaxPixelSize.map { "\($0) px long side" } ?? "full size")",
            "- Photos: \(photos.count) (\(photos.count { $0.error != nil }) unreadable)",
        ]
        let read = photos.compactMap(\.result)
        let recipes = read.flatMap(\.recipes)
        let seconds = photos.map(\.seconds).sorted()
        lines += [
            "- Recipe photos: \(read.count { $0.kind == .recipe }); recipes: \(recipes.count); ingredients: \(recipes.reduce(0) { $0 + $1.ingredients }) (\(recipes.reduce(0) { $0 + $1.unparsedIngredients }) unparsed); steps: \(recipes.reduce(0) { $0 + $1.steps })",
            "- Page numbers read: \(read.count { $0.pageNumber != nil }) of \(read.count)",
            "- Seconds a photo: median \(seconds.isEmpty ? "–" : String(format: "%.2f", seconds[seconds.count / 2])), slowest \(seconds.last.map { String(format: "%.2f", $0) } ?? "–")",
            "- Skew after cleanup (degrees, absolute): median \(Self.format(Self.median(photos.compactMap { $0.scan?.skewDegrees }.map(abs)))), largest \(Self.format(photos.compactMap { $0.scan?.skewDegrees }.map(abs).max())); lines in another script set aside: \(photos.reduce(0) { $0 + ($1.scan?.nonLatinLines ?? 0) })",
            "",
            "| File | Kind | Turns | Blocks | Lines | Recipes | Ingredients | Unparsed | Steps | Page | Gate | Seconds |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|",
        ]
        for photo in photos {
            guard let result = photo.result, let scan = photo.scan else {
                lines.append("| \(photo.fileName) | unreadable | | | | | | | | | | \(String(format: "%.2f", photo.seconds)) |")
                continue
            }
            let ingredients = result.recipes.reduce(0) { $0 + $1.ingredients }
            let unparsed = result.recipes.reduce(0) { $0 + $1.unparsedIngredients }
            let steps = result.recipes.map { String($0.steps) }.joined(separator: " + ")
            var kind = result.kind.rawValue + (result.isContinuation ? " (continues)" : "")
            if let reference = result.referenceKind { kind += " · \(reference) \(result.referenceSections ?? 0)" }
            if let contents = result.contents { kind += result.kind == .index ? " · \(contents.entries)" : " · \(contents.sections)/\(contents.entries)/\(contents.paged)" }
            if let suppliers = result.suppliers { kind += " · \(suppliers)" }
            lines.append("| \(photo.fileName) | \(kind) | \(result.quarterTurns) | \(scan.blocks.count) | \(scan.blocks.reduce(0) { $0 + $1.lines.count }) | \(result.recipes.count) | \(ingredients) | \(unparsed) | \(steps.isEmpty ? "0" : steps) | \(result.pageNumber.map(String.init) ?? "–") | \(photo.quality?.quality.label ?? "–") | \(String(format: "%.2f", photo.seconds)) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    static func format(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "–"
    }
}
