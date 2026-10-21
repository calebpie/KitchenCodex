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

/// Recipes → Add → Scan Page (02 Flow B): pages from the camera, read one by one as they are taken,
/// or photos chosen from Photos or Files, read in order with the page pipeline; a book named by a
/// barcode among them or chosen; then each reading reviewed when it must be and saved straight when
/// it need not.
@MainActor
@Observable
final class ScanSession: PageCaptureSink {
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
        /// A camera capture in Photo mode: a picture for a recipe, never a recipe itself.
        var isPhoto = false
        /// The photo turned out to be the book's barcode (ux-notes row 65).
        var isbn: String?
    }

    /// One page from the camera: the cleaned page on disk, the gate's reading of the photo before
    /// cleanup, and its own reading once the queue gets to it. A capture deleted from the captures
    /// sheet stays in place, marked, so the queue's positions hold.
    struct CameraCapture {
        let id: Int
        let url: URL
        var mode: CaptureMode
        let quality: PageQualityReading?
        let note: String
        var reading: PageReading?
        var isDeleted = false
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
    /// The book a barcode among the photos, or one scanned at the camera's start, named.
    private(set) var barcodeBook: Book?
    /// A barcode for a book not on the shelf: Add Cookbook's card for it (ux-notes row 65).
    var newBookISBN: String?
    var isSaving = false

    // The camera's run.
    private(set) var captures: [CameraCapture] = []
    /// The last recipe capture's text blocks in reading order, for the iPad's running preview
    /// (03 §3.5, ux-notes row 87).
    private(set) var lastCapturePreview: [CapturePreviewBlock] = []
    /// Whether the queue is still reading a capture.
    private(set) var isReadingCaptures = false
    /// Three captures in a row hazy and poorly read: the camera asks to clean the lens (ux-notes
    /// row 57). Reset once asked.
    var asksToCleanLens = false
    private var lens = LensWatch()
    private var nextCaptureID = 0
    private var captureQueue: Task<Void, Never>?
    /// Photo-mode captures by the recipe they go with: (reading, recipe on it).
    private var coverCandidates: [[Int]: [URL]] = [:]
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
        captureQueue?.cancel()
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
        await nameBook(isbn: await takeBarcodes())
    }

    /// After reading: the book a barcode named, else Which book? when the scan didn't start from one.
    private func nameBook(isbn: String?) async {
        if let isbn, startingBook == nil {
            if let shelved = shelfBook(isbn: isbn) {
                book = shelved
                barcodeBook = shelved
            } else {
                // Add Cookbook's card, over Which book?, which stays if the cook cancels it.
                newBookISBN = isbn
                phase = .whichBook
                return
            }
        }
        if book == nil { phase = .whichBook } else { await advance() }
    }

    /// The book Add Cookbook added for the barcode: the scan goes on with it.
    func addedBook(_ added: Book) {
        newBookISBN = nil
        barcodeBook = added
        choose(added)
    }

    // MARK: - A barcode among the pages

    /// Photos that read as an ISBN barcode name the book and leave the scan (ux-notes row 65): only
    /// photos that aren't recipes are tried, so pages cost nothing. The first ISBN found.
    private func takeBarcodes() async -> String? {
        var found: String?
        for reading in readings where reading.kind != .recipe && reading.files.count == 1 {
            guard let url = urls.first(where: { $0.lastPathComponent == reading.files[0] }),
                  let isbn = await Self.isbn(at: url) else { continue }
            found = found ?? isbn
            readings.removeAll { $0.files == reading.files }
            if let index = urls.firstIndex(of: url) { update(index) { $0.isbn = isbn } }
        }
        return found
    }

    @concurrent
    nonisolated private static func isbn(at url: URL) async -> String? {
        try? await ISBNBarcode.read(contentsOf: url)
    }

    /// The shelf's book with this ISBN.
    func shelfBook(isbn: String) -> Book? {
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.isbn == isbn })
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - The camera

    /// The folder the camera writes its cleaned pages to.
    func captureFolder() -> URL {
        if let folder { return folder }
        let folder = FileManager.default.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        return folder
    }

    // MARK: - The camera's sink

    var namesBookByBarcode: Bool { startingBook == nil }

    func reserveCaptureID() -> Int {
        defer { nextCaptureID += 1 }
        return nextCaptureID
    }

    var captureItems: [CaptureItem] {
        captures.filter { !$0.isDeleted }.map { capture in
            CaptureItem(id: capture.id, url: capture.url, mode: capture.mode, note: capture.note, detail: Self.detail(of: capture))
        }
    }

    /// What a capture read as, for the captures sheet.
    private static func detail(of capture: CameraCapture) -> String? {
        guard let reading = capture.reading else { return "Reading…" }
        if capture.mode == .photo { return reading.pageNumber.map { "A photo for a recipe, p. \($0)" } ?? "A photo for a recipe" }
        guard reading.kind == .recipe else { return "Not a recipe: \(reading.kind.title.lowercased())" }
        let titles = reading.recipes.map(\.title).filter { !$0.isEmpty }
        let page = reading.pageNumber.map { " · p. \($0)" } ?? ""
        if let first = titles.first { return (titles.count > 1 ? "“\(first)” and \(titles.count - 1) more" : "“\(first)”") + page }
        return reading.isContinuation ? "Continues the page before" + page : "A recipe" + page
    }

    /// Deleted from the captures sheet: out of the queue and the scan (ux-notes row 83).
    func removeCapture(id: Int) {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        captures[index].isDeleted = true
        try? FileManager.default.removeItem(at: captures[index].url)
        progress.removeAll { $0.id == index }
        if captures.allSatisfy(\.isDeleted) { lastCapturePreview = [] }
    }

    /// A capture made a recipe page or a photo after the fact: it is read either way, so only what
    /// Done does with it changes.
    func setMode(_ mode: CaptureMode, ofCapture id: Int) {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        captures[index].mode = mode
        update(index) { $0.isPhoto = mode == .photo }
    }

    /// A page from the camera, read at once in capture order behind the ones before it, so the
    /// processing sheet has little left when the cook taps Done. A Photo capture is read only for
    /// its page number.
    func addCapture(id: Int, at url: URL, mode: CaptureMode, quality: PageQualityReading?, note: String) {
        let index = captures.count
        captures.append(CameraCapture(id: id, url: url, mode: mode, quality: quality, note: note))
        var page = PageProgress(id: index)
        page.isPhoto = mode == .photo
        progress.append(page)
        isReadingCaptures = true
        let previous = captureQueue
        let pipeline = pipeline
        captureQueue = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let (stream, continuation) = AsyncStream.makeStream(of: PagePipeline.Stage.self)
            let reader = Task { try await Self.readPage(url, index: index, quality: quality, with: pipeline, reporting: continuation) }
            for await stage in stream { apply(stage) }
            let reading = try? await reader.value
            captures[index].reading = reading
            if let reading, captures[index].mode == .recipe, !captures[index].isDeleted { noteCapture(reading, quality: quality) }
            if index == captures.count - 1 { isReadingCaptures = false }
        }
    }

    @concurrent
    nonisolated static func readPage(_ url: URL, index: Int, quality: PageQualityReading?, with pipeline: PagePipeline, reporting continuation: AsyncStream<PagePipeline.Stage>.Continuation) async throws -> PageReading {
        defer { continuation.finish() }
        return try await pipeline.readPage(contentsOf: url, page: index, of: index + 1, quality: quality) { continuation.yield($0) }
    }

    /// The iPad's preview, and the run of hazy captures: Clean the lens stays advisory until three
    /// captures in a row both score Apple's smudge threshold and read poorly (ux-notes row 57).
    private func noteCapture(_ reading: PageReading, quality: PageQualityReading?) {
        lastCapturePreview = reading.previewBlocks
        if lens.note(reading, quality: quality) { asksToCleanLens = true }
    }

    /// The barcode scanned live at the camera's start.
    var scannedISBN: String?

    /// The camera's Close: its pages let go.
    func discardCaptures() {
        captureQueue?.cancel()
        captureQueue = nil
        for capture in captures { try? FileManager.default.removeItem(at: capture.url) }
        captures = []
        progress = []
        lastCapturePreview = []
        isReadingCaptures = false
        scannedISBN = nil
        lens.reset()
    }

    /// The camera's Done: the rest of the queue read, the recipe pages stitched and refined, the
    /// Photo captures matched to their recipes, then the book and the queue as for chosen photos.
    func finishCapturing() async {
        guard captures.contains(where: { !$0.isDeleted }) else { return }
        phase = .processing
        await captureQueue?.value
        captures.removeAll(where: \.isDeleted)
        progress = captures.indices.map { index in
            var page = PageProgress(id: index, step: .done)
            page.isPhoto = captures[index].mode == .photo
            if let reading = captures[index].reading {
                page.kind = reading.kind
                page.recipes = reading.recipes.count
                page.ingredients = reading.recipes.reduce(0) { $0 + $1.ingredients.count }
                page.steps = reading.recipes.reduce(0) { $0 + $1.steps.count }
            }
            return page
        }
        urls = captures.map(\.url)
        let pages = captures.filter { $0.mode == .recipe }.compactMap(\.reading)
        let pipeline = pipeline
        let urls = urls
        let (stream, continuation) = AsyncStream.makeStream(of: PagePipeline.Stage.self)
        let finisher = Task { await Self.finish(pages, urls: urls, with: pipeline, reporting: continuation) }
        for await stage in stream { apply(stage) }
        readings = await finisher.value
        refining = nil
        matchPhotoCaptures()
        Self.logger.info("Scan Page: \(self.captures.count) captures (\(self.captures.count { $0.mode == .photo }) photos), \(self.readings.count) readings")
        guard !Task.isCancelled else { return }
        let barcode = await takeBarcodes()
        await nameBook(isbn: scannedISBN ?? barcode)
    }

    @concurrent
    nonisolated static func finish(_ pages: [PageReading], urls: [URL], with pipeline: PagePipeline, reporting continuation: AsyncStream<PagePipeline.Stage>.Continuation) async -> [PageReading] {
        defer { continuation.finish() }
        return await pipeline.finish(pages, urls: urls) { continuation.yield($0) }
    }

    /// Each Photo capture goes with the recipe that points to its page ("photograph on page 12",
    /// read earlier in the session), or else the recipe read before it, or the first after it when
    /// it came first (04 §5.1 "Printed photos").
    private func matchPhotoCaptures() {
        coverCandidates = [:]
        let order = Dictionary(captures.enumerated().map { ($0.element.url.lastPathComponent, $0.offset) }, uniquingKeysWith: { first, _ in first })
        // Each recipe with the capture it was read from.
        let recipes = readings.enumerated().flatMap { index, reading in
            reading.recipes.indices.map { (key: [index, $0], capture: order[reading.files.first ?? ""] ?? 0, recipe: reading.recipes[$0]) }
        }
        for (position, capture) in captures.enumerated() where capture.mode == .photo {
            let page = capture.reading?.pageNumber
            let earlier = recipes.filter { $0.capture < position }
            let pointed = page.flatMap { page in
                earlier.last { $0.recipe.crossReferences.contains { $0.kind == .photograph && $0.pages.contains(page) } }
            }
            guard let target = pointed ?? earlier.last ?? recipes.first(where: { $0.capture > position }) else { continue }
            coverCandidates[target.key, default: []].append(capture.url)
        }
    }

    /// The Photo captures for recipe `index` of the reading under way.
    private func candidates(forRecipe index: Int) -> [URL] {
        coverCandidates[[position, index]] ?? []
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
        guard let index = progress.firstIndex(where: { $0.id == page }) else { return }
        change(&progress[index])
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
            let course = Self.lastCourse(of: book)
            for index in model.recipes.indices {
                model.recipes[index].reasons = reasons[index]
                model.recipes[index].course = course
            }
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
                await ScanSaving.attachCoverCandidates(candidates(forRecipe: index), to: recipe, in: modelContext)
                saved.append(SavedRecipe(recipe: recipe, reviewed: false))
            }
            isSaving = false
            position += 1
        }
        review = nil
        phase = .finished
    }

    /// The course last chosen for a book: its latest recipe's that has one (ux-notes row 73). A
    /// book is scanned chapter by chapter, so a recipe saved straight takes it too.
    static func lastCourse(of book: Book?) -> String? {
        (book?.recipes ?? []).filter { $0.course != nil }.max { $0.createdAt < $1.createdAt }?.course
    }

    /// Review's Save: every recipe on the page not skipped, as reviewed.
    func saveReview() async {
        guard let review else { return }
        isSaving = true
        for index in review.recipes.indices where !review.recipes[index].isSkipped {
            let recipe = await ScanSaving.saveNew(review, recipe: index, book: book, reviewed: true, images: images, in: modelContext)
            await ScanSaving.attachCoverCandidates(candidates(forRecipe: index), to: recipe, in: modelContext)
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
