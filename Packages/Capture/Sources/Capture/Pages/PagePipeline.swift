import CoreGraphics
import Foundation
import Intelligence

/// Reads photographed cookbook pages into recipes (02 Flow B steps 2–5, Flow C step 5): the quality
/// gate, the reader, the deterministic structurer, stitching for a recipe over several pages, and
/// the on-device model only where the deterministic reading lacks a title, ingredients or steps
/// (Phase 1 slice 10's rule, applied to pages): first on the page's text, then, when the model
/// takes images and the text pass still falls short, on the photo as well.
public struct PagePipeline: Sendable {
    public var gate: PageQualityGate
    public var reader: PageReader
    public var structurer: PageStructurer
    /// The second (and third) pass; nil keeps the reading deterministic.
    public var model: (any PageStructuring)?
    /// Whether the third pass may send the photo when the model takes images.
    public var usesImageInput: Bool

    public init(gate: PageQualityGate = PageQualityGate(), reader: PageReader = PageReader(), structurer: PageStructurer = PageStructurer(), model: (any PageStructuring)? = nil, usesImageInput: Bool = true) {
        self.gate = gate
        self.reader = reader
        self.structurer = structurer
        self.model = model
        self.usesImageInput = usesImageInput
    }

    /// What the pipeline is doing, for Flow B's processing sheet (02 Flow B step 4: "Reading text…
    /// Finding ingredients… Finding steps…", each stage real). Pages count from 0.
    public enum Stage: Sendable, Equatable {
        /// The quality gate is measuring the photo.
        case checking(page: Int, of: Int)
        /// The gate has read the photo (never blocking); the recognizer is reading its text.
        case reading(page: Int, of: Int, quality: PageQualityReading)
        /// The text is read; the structurer is finding the ingredients and steps.
        case structuring(page: Int, of: Int, lines: Int)
        /// The page is read.
        case read(page: Int, of: Int, kind: PageKind, recipes: Int, ingredients: Int, steps: Int)
        /// The on-device model is reading a recipe whose deterministic reading falls short
        /// (`wantsModel`).
        case refining(title: String)
    }

    /// Reports a stage; called on the pipeline's own executor, so it should only hand the stage on.
    public typealias Progress = @Sendable (Stage) -> Void

    /// One photo: gate, read, structure. The model pass, when there is a model, runs on recipes that
    /// need it (`wantsModel`); a page that continues a recipe is left for stitching.
    public func read(contentsOf url: URL) async throws -> PageReading {
        try await read(contentsOf: url, page: 0, of: 1, progress: nil)
    }

    func read(contentsOf url: URL, page: Int, of count: Int, quality: PageQualityReading? = nil, progress: Progress?) async throws -> PageReading {
        let image = try PageImage.load(contentsOf: url, maxPixelSize: reader.maxPixelSize)
        var reading = try await readPage(image, file: url.lastPathComponent, page: page, of: count, quality: quality, progress: progress).reading
        if model != nil, !reading.isContinuation {
            reading = await refine(reading, image: image, progress: progress)
        }
        return reading
    }

    /// One photo of a run, deterministic: gate (unless the caller measured the photo already, as the
    /// camera does on the capture before cleanup), read, structure, with each stage reported. The
    /// model and stitching wait for `finish(_:urls:progress:)`, so a camera session can read each
    /// capture as it is taken.
    public func readPage(contentsOf url: URL, page: Int, of count: Int, quality: PageQualityReading? = nil, progress: Progress? = nil) async throws -> PageReading {
        let image = try PageImage.load(contentsOf: url, maxPixelSize: reader.maxPixelSize)
        return try await readPage(image, file: url.lastPathComponent, page: page, of: count, quality: quality, progress: progress).reading
    }

    /// A photo chosen as a contents page (Build the Recipe List): read as `readPage` reads it, with
    /// the page's outline found whatever kind the structurer made of it, for `ContentsReader`.
    public func readContentsPage(contentsOf url: URL) async throws -> PageReading {
        let image = try PageImage.load(contentsOf: url, maxPixelSize: reader.maxPixelSize)
        return try await readPage(image, file: url.lastPathComponent, page: 0, of: 1, quality: nil, progress: nil, findsOutline: true).reading
    }

    /// What one photo gave at each step, for Read Fixtures' report (04 §5.1 "Device readings"): the
    /// reader's scan, the margin lines read again when no folio was found, and the reading.
    public struct PageRead: Sendable {
        public var reading: PageReading
        public var scan: PageScan
        public var marginLines: [String]?
        public var quality: PageQualityReading
    }

    /// One photo read as `readPage` reads it, with the reader's scan kept (no model).
    public func readForReport(contentsOf url: URL) async throws -> PageRead {
        let image = try PageImage.load(contentsOf: url, maxPixelSize: reader.maxPixelSize)
        return try await readPage(image, file: url.lastPathComponent, page: 0, of: 1, quality: nil, progress: nil)
    }

    func readPage(_ image: CGImage, file: String, page: Int, of count: Int, quality known: PageQualityReading?, progress: Progress?, findsOutline: Bool = false) async throws -> PageRead {
        let clock = ContinuousClock()
        let start = clock.now
        progress?(.checking(page: page, of: count))
        let quality: PageQualityReading
        if let known { quality = known } else { quality = await gate.assess(image) }
        progress?(.reading(page: page, of: count, quality: quality))
        var scan = try await reader.read(image)
        scan.duration = clock.now - start
        progress?(.structuring(page: page, of: count, lines: scan.blocks.reduce(0) { $0 + $1.lines.count }))
        var reading = structurer.read(scan, file: file, quality: quality)
        var marginLines: [String]?
        if reading.pageNumber == nil, reading.kind == .recipe || reading.kind == .prose {
            // The folio's small type, read again from the page's foot and head.
            let margins = await reader.marginLines(of: image, paper: scan.paper)
            marginLines = margins
            if let number = PageStructurer.folioNumber(in: margins) { reading.pageNumbers = [number] }
        }
        if findsOutline || reading.kind == .contents || reading.kind == .index {
            reading.outline = await PageCleanup.detectOutline(in: image, quarterTurns: scan.quarterTurns)
        }
        reading.durations = [clock.now - start]
        progress?(.read(page: page, of: count, kind: reading.kind, recipes: reading.recipes.count,
                        ingredients: reading.recipes.reduce(0) { $0 + $1.ingredients.count },
                        steps: reading.recipes.reduce(0) { $0 + $1.steps.count }))
        return PageRead(reading: reading, scan: scan, marginLines: marginLines, quality: quality)
    }

    /// Consecutive photos in capture order, read and stitched: a page that opens without a title
    /// continues the recipe before it. The model pass runs on the stitched readings.
    public func read(contentsOf urls: [URL], progress: Progress? = nil) async throws -> [PageReading] {
        var readings: [PageReading] = []
        for (page, url) in urls.enumerated() {
            readings.append(try await readPage(contentsOf: url, page: page, of: urls.count, progress: progress))
        }
        return await finish(readings, urls: urls, progress: progress)
    }

    /// The run's single-page readings (`readPage`) stitched, then refined by the model where a
    /// recipe falls short. `urls` holds the photos by file name, for the model's image pass.
    public func finish(_ readings: [PageReading], urls: [URL], progress: Progress? = nil) async -> [PageReading] {
        var stitched = PageStitcher.stitch(readings)
        if model != nil {
            for index in stitched.indices {
                let image = stitched[index].files.first.flatMap { file in urls.first { $0.lastPathComponent == file } }
                    .flatMap { try? PageImage.load(contentsOf: $0, maxPixelSize: 1600) }
                stitched[index] = await refine(stitched[index], image: image, progress: progress)
            }
        }
        return stitched
    }

    // MARK: - The model

    /// Whether the model should read the recipe: it lacks a title, two ingredients or a step.
    public static func wantsModel(_ recipe: PageRecipe) -> Bool {
        !recipe.isComplete
    }

    /// Asks the model about each recipe that wants it and keeps what it reads only where it does
    /// better than the deterministic reading. Readings without a model, or with nothing to refine,
    /// come back unchanged.
    public func refine(_ reading: PageReading, image: CGImage?, progress: Progress? = nil) async -> PageReading {
        guard let model, model.isAvailable, reading.kind == .recipe else { return reading }
        var refined = reading
        // A first recipe that continues a page before the photos (nothing to stitch it to) is the
        // cook's to name or skip, not the model's.
        for index in refined.recipes.indices where Self.wantsModel(refined.recipes[index]) && !(index == 0 && reading.isContinuation) {
            let text = Self.text(of: refined.recipes[index], in: refined)
            guard !text.isEmpty else { continue }
            progress?(.refining(title: refined.recipes[index].title))
            var recipe = refined.recipes[index]
            if let draft = try? await model.structure(pageText: text) {
                recipe = Self.merge(draft, into: recipe)
            }
            if Self.wantsModel(recipe), usesImageInput, model.acceptsImages, let image,
               let draft = try? await model.structure(pageText: text, image: image) {
                recipe = Self.merge(draft, into: recipe)
            }
            refined.recipes[index] = recipe
        }
        return refined
    }

    /// The recipe's text in reading order, for the model: its title, then every block it drew on.
    static func text(of recipe: PageRecipe, in reading: PageReading) -> String {
        var ids = Set(recipe.ingredients.map(\.block))
        recipe.steps.forEach { ids.formUnion($0.blocks) }
        let title = recipe.title.isEmpty ? [] : [recipe.title]
        let roles: Set<PageBlock.Role> = [.headnote, .yield, .time, .ingredientGroup, .note]
        let blocks = reading.blocks.filter { ids.contains($0.id) || ($0.role.map(roles.contains) ?? ($0.kind != .photo && $0.role == nil)) }
        return (title + blocks.map(\.text)).joined(separator: "\n")
    }

    /// The model's reading over the deterministic one, part by part: the deterministic title and
    /// yield stand when there are any; ingredients and steps are the model's only where the
    /// deterministic reading had too few. Model-read parts are marked `.model` and the recipe's
    /// confidence is held at the model's.
    static func merge(_ draft: StructuredPageDraft, into recipe: PageRecipe) -> PageRecipe {
        var merged = recipe
        var used = false
        if merged.title.isEmpty, !draft.title.isEmpty {
            merged.title = PageLines.titleText(draft.title)
            used = true
        }
        if merged.yield == nil { merged.yield = draft.yield.map(PageLines.yieldText) }
        if merged.headnote == nil { merged.headnote = draft.headnote }
        if merged.ingredients.count < 2, draft.ingredients.count >= 2 {
            merged.ingredients = draft.ingredients.map { line in
                let text = PageLines.ingredientText(line)
                let parsed = IngredientParser.parse(text)
                let unparsed = PageLines.isUnparsed(text, parsed: parsed)
                return PageIngredient(text: text, parsed: parsed, confidence: PageLines.parserConfidence(parsed, unparsed: unparsed), isUnparsed: unparsed, block: -1)
            }
            used = true
        }
        if merged.steps.isEmpty, !draft.steps.isEmpty {
            merged.steps = draft.steps.map { PageStep(text: $0, blocks: []) }
            used = true
        }
        if used {
            merged.method = .model
            let parsed = merged.ingredients.isEmpty ? 0 : Double(merged.ingredients.count { !$0.isUnparsed }) / Double(merged.ingredients.count)
            var structure = 0.0
            if !merged.title.isEmpty { structure += 0.25 }
            if merged.ingredients.count >= 2 { structure += 0.3 }
            if !merged.steps.isEmpty { structure += 0.3 }
            if merged.yield != nil { structure += 0.05 }
            if merged.unassignedBlocks.isEmpty { structure += 0.1 }
            merged.confidence = PageConfidence(ocr: recipe.confidence.ocr, parser: parsed, structure: structure, model: draft.confidence)
        }
        return merged
    }
}
