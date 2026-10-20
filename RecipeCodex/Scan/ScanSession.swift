import Capture
import Intelligence
import Observation
import OSLog
import PhotosUI
import RecipeModel
import SwiftData
import SwiftUI

/// When scan review is asked for (04 §5.1 "Scan review", 02 Flow B step 5).
enum ScanGate {
    /// The reasons that force review before saving: the book's first recipe and a layout not yet
    /// confirmed. The others save straight and ask for a look through Needs a Look.
    static let forcing: Set<ReviewReason> = [.firstRecipeOfBook, .unseenLayout]

    /// Each recipe's reasons in `reading`, given the book: whether it has a recipe yet and the
    /// layouts the cook has confirmed. A later recipe on the same page is not the book's first. A
    /// page with no book (a recipe card, a clipping) has no confirmed layout, so it is reviewed.
    static func reasons(for reading: PageReading, book: Book?) -> [[ReviewReason]] {
        var hasRecipes = book.map { !($0.recipes ?? []).isEmpty } ?? true
        let layouts = Set(book?.reviewedLayouts ?? [])
        return reading.recipes.map { recipe in
            defer { hasRecipes = true }
            return recipe.reviewReasons(bookHasRecipes: hasRecipes, reviewedLayouts: layouts)
        }
    }

    static func isForced(_ reasons: [[ReviewReason]]) -> Bool {
        reasons.contains { !forcing.isDisjoint(with: $0) }
    }
}

/// Recipes → Add → Scan Page (02 Flow B, without the camera until slice 4): photos chosen from
/// Photos or Files, read in order with the page pipeline, a book chosen, then each reading reviewed
/// when it must be and saved straight when it need not.
@MainActor
@Observable
final class ScanSession {
    enum Phase: Equatable {
        case choosing
        case loading
        case processing
        case whichBook
        case reviewing
        case notRecipe
        case finished
        case failed(String)
    }

    /// One photo's progress through the pipeline, for the processing sheet.
    struct PageProgress: Identifiable, Equatable {
        enum Step: Int, Comparable {
            case waiting, checking, reading, structuring, done
            static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
        }

        let id: Int
        var step = Step.waiting
        var quality: PageQualityReading?
        var lines: Int?
        var kind: PageKind?
        var recipes = 0
        var ingredients = 0
        var steps = 0
    }

    /// What one saved recipe was, for the summary.
    struct SavedRecipe: Identifiable {
        let recipe: Recipe
        let reviewed: Bool
        var id: PersistentIdentifier { recipe.persistentModelID }
    }

    var phase = Phase.choosing
    /// The book the scan started from; nil asks Which book? after reading.
    let startingBook: Book?
    private(set) var book: Book?
    private(set) var progress: [PageProgress] = []
    /// The recipe the on-device model is reading, while it reads.
    private(set) var refining: String?
    private(set) var readings: [PageReading] = []
    private(set) var position = 0
    private(set) var review: ScanReviewModel?
    private(set) var saved: [SavedRecipe] = []
    private(set) var keptPages = 0
    private(set) var discardedPages = 0
    var isSaving = false
    /// Set by the sheet, which owns the environment's context.
    var modelContext: ModelContext!

    private var urls: [URL] = []
    private var folder: URL?
    private var reviewStarted: ContinuousClock.Instant?
    private var work: Task<Void, Never>?
    private let images = ScanSaving.PageImages()

    private static let logger = Logger(subsystem: "com.calebpietrafesa.RecipeCodex", category: "scan")

    init(book: Book?) {
        startingBook = book
        self.book = book
    }

    var reading: PageReading? { readings.indices.contains(position) ? readings[position] : nil }

    /// The pipeline: the deterministic reading, and the on-device model only where it falls short
    /// (`PagePipeline.wantsModel`). In the iOS Simulator Vision's document reader returns line
    /// fragments at the wrong places on a full 24-megapixel photo, where a 4,096-pixel copy reads as
    /// the Mac reads the full one; a device reads the photo at full size, as the harness does.
    private var pipeline: PagePipeline { Self.makePipeline() }

    static func makePipeline() -> PagePipeline {
        #if targetEnvironment(simulator)
        let reader = PageReader(maxPixelSize: 4_096)
        #else
        let reader = PageReader()
        #endif
        return PagePipeline(reader: reader, model: OnDevicePageStructurer())
    }

    func cancel() {
        work?.cancel()
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: - Choosing photos

    /// Photos chosen in Photos, in the order chosen.
    func start(with items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        phase = .loading
        work = Task {
            var files: [(Data, String)] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                files.append((data, item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"))
            }
            await read(files)
        }
    }

    /// Image files chosen in Files.
    func start(with fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        phase = .loading
        work = Task {
            var files: [(Data, String)] = []
            for url in fileURLs {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                files.append((data, url.pathExtension.isEmpty ? "jpg" : url.pathExtension))
            }
            await read(files)
        }
    }

    private func read(_ files: [(Data, String)]) async {
        guard !files.isEmpty else {
            phase = .failed("Those photos couldn't be opened. Try choosing them again.")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        urls = files.enumerated().compactMap { index, file in
            let url = folder.appending(path: "page-\(index + 1).\(file.1)")
            return (try? file.0.write(to: url)) != nil ? url : nil
        }
        await process()
    }

    // MARK: - Reading

    /// Runs the pipeline over the photos in order, stitching a recipe over a page turn, with each
    /// stage shown as it happens.
    private func process() async {
        phase = .processing
        progress = urls.indices.map { PageProgress(id: $0) }
        let clock = ContinuousClock()
        let started = clock.now
        let (stream, continuation) = AsyncStream.makeStream(of: PagePipeline.Stage.self)
        let urls = urls
        let pipeline = pipeline
        let reader = Task { try await Self.read(urls, with: pipeline, reporting: continuation) }
        for await stage in stream { apply(stage) }
        do {
            readings = try await reader.value
        } catch {
            phase = .failed("The photos couldn't be read. Choose them again, or try other photos.")
            return
        }
        refining = nil
        let seconds = (clock.now - started).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
        Self.logger.info("Scan Page: \(urls.count) photos read in \(seconds, privacy: .public) (\(self.readings.count) readings, \(self.readings.reduce(0) { $0 + $1.recipes.count }) recipes)")
        guard !Task.isCancelled else { return }
        if book == nil { phase = .whichBook } else { await advance() }
    }

    /// The pipeline off the main actor (Vision and the structurer take a second or two a page),
    /// each stage handed back in order.
    @concurrent
    nonisolated static func read(_ urls: [URL], with pipeline: PagePipeline, reporting continuation: AsyncStream<PagePipeline.Stage>.Continuation) async throws -> [PageReading] {
        defer { continuation.finish() }
        return try await pipeline.read(contentsOf: urls) { continuation.yield($0) }
    }

    private func apply(_ stage: PagePipeline.Stage) {
        switch stage {
        case let .checking(page, _):
            update(page) { $0.step = .checking }
        case let .reading(page, _, quality):
            update(page) { $0.step = .reading; $0.quality = quality }
        case let .structuring(page, _, lines):
            update(page) { $0.step = .structuring; $0.lines = lines }
        case let .read(page, _, kind, recipes, ingredients, steps):
            update(page) {
                $0.step = .done
                $0.kind = kind
                $0.recipes = recipes
                $0.ingredients = ingredients
                $0.steps = steps
            }
        case let .refining(title):
            refining = title.isEmpty ? "the recipe" : "“\(title)”"
        }
    }

    private func update(_ page: Int, _ change: (inout PageProgress) -> Void) {
        guard progress.indices.contains(page) else { return }
        change(&progress[page])
    }

    // MARK: - Which book?

    /// The cook's answer to Which book?: a book on the shelf, a new one, or none (a recipe card).
    func choose(_ book: Book?) {
        self.book = book
        work = Task { await advance() }
    }

    // MARK: - The queue

    /// Goes through the readings in order: a page that is not a recipe asks what to keep; a reading
    /// that must be reviewed waits for the cook; the rest save straight, "Accepted automatically".
    private func advance() async {
        while let reading {
            guard reading.kind == .recipe, !reading.recipes.isEmpty else {
                review = ScanReviewModel(reading: reading, urls: urls)
                phase = .notRecipe
                return
            }
            let reasons = ScanGate.reasons(for: reading, book: book)
            let model = ScanReviewModel(reading: reading, urls: urls)
            for index in model.recipes.indices { model.recipes[index].reasons = reasons[index] }
            // The first photo opening mid-recipe continues a page that wasn't scanned: shown, but
            // skipped unless the cook includes it.
            if position == 0, reading.isContinuation, model.recipes.count > 1 {
                model.recipes[0].isSkipped = true
            }
            // A recipe with no title is never accepted automatically.
            let untitled = model.recipes.contains { $0.title?.text.trimmed.isEmpty != false && !$0.isSkipped }
            if ScanGate.isForced(reasons) || untitled || model.recipes.contains(where: \.isSkipped) {
                review = model
                phase = .reviewing
                reviewStarted = .now
                return
            }
            isSaving = true
            for index in model.recipes.indices {
                let recipe = await ScanSaving.saveNew(model, recipe: index, book: book, reviewed: false, images: images, in: modelContext)
                saved.append(SavedRecipe(recipe: recipe, reviewed: false))
            }
            isSaving = false
            position += 1
        }
        review = nil
        phase = .finished
    }

    /// Review's Save: every recipe on the page not skipped, as reviewed.
    func saveReview() async {
        guard let review else { return }
        isSaving = true
        for index in review.recipes.indices where !review.recipes[index].isSkipped {
            let recipe = await ScanSaving.saveNew(review, recipe: index, book: book, reviewed: true, images: images, in: modelContext)
            saved.append(SavedRecipe(recipe: recipe, reviewed: true))
        }
        isSaving = false
        if let reviewStarted {
            let seconds = (ContinuousClock.now - reviewStarted).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
            let skipped = review.recipes.count(where: \.isSkipped)
            Self.logger.info("Scan review: saved after \(seconds, privacy: .public) (\(review.recipes.count - skipped) recipes, \(skipped) skipped, \(review.undoStack.count) changes)")
        }
        position += 1
        await advance()
    }

    /// Reads the photos under review again, the cook's changes dropped (review → More → Rescan).
    func rescan() async {
        guard let reading else { return }
        let files = reading.files.compactMap { file in urls.first { $0.lastPathComponent == file } }
        phase = .processing
        progress = files.indices.map { PageProgress(id: $0) }
        let pipeline = pipeline
        let (stream, continuation) = AsyncStream.makeStream(of: PagePipeline.Stage.self)
        let reader = Task { try await Self.read(files, with: pipeline, reporting: continuation) }
        for await stage in stream { apply(stage) }
        refining = nil
        if let fresh = try? await reader.value.first {
            readings[position] = fresh
        }
        await advance()
    }

    /// A page that is not a recipe: kept on `book` as a page scan, or let go.
    func keepPage(on book: Book?) async {
        if let book, let review, let kind = reading?.kind {
            isSaving = true
            await ScanSaving.keepPageScan(review, kind: kind, book: book, images: images, in: modelContext)
            isSaving = false
            keptPages += 1
        } else {
            discardedPages += 1
        }
        position += 1
        await advance()
    }
}
