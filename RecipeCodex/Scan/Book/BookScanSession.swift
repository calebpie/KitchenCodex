import Capture
import Foundation
import Observation
import OSLog
import PhotosUI
import RecipeModel
import SwiftData
import SwiftUI

/// The whole-book session (03 §3.8, 02 Flow C steps 4–7): captures from the camera (or, in the
/// Simulator, photos and files), read and saved off the capture path in the session's queue while
/// the cook keeps shooting. Page numbers read off the scans keep the punchlist in step: a recipe
/// whose page matches an entry marks it captured and the current item moves to the next one not
/// captured; a page with no number is the current item; two recipes on a page are both saved
/// (04 §5.1 "Sub-recipes on one page"), each matched by page then title; Photo captures go to the
/// recipe that points to them, or the one before, as cover candidates. Every recipe saves straight
/// ("Accepted automatically"); the book's first recipe of each layout, a capture the cook flagged
/// Needs Review and a reading of low confidence also go to the review queue.
///
/// The queue is the state in the book's scan folder (`BookScanState`): Close pauses with nothing
/// lost, captures still reading finish, and a relaunch resumes them (`BookScanStore.resume`). A
/// background task could drive the same `drain()` later; none is registered (no `BGProcessingTask`
/// without the processing background mode).
@MainActor
@Observable
final class BookScanSession: PageCaptureSink {
    let book: Book
    let bookID: UUID
    private(set) var state: BookScanState
    /// Whether a view shows the session.
    private(set) var isOpen = false
    var asksToCleanLens = false
    /// The book session knows its book: a barcode names nothing.
    var scannedISBN: String?
    private(set) var lastCapturePreview: [CapturePreviewBlock] = []
    /// Readings of this sitting's captures, for the last capture's pane and for joining a page that
    /// continues the one before.
    private(set) var readings: [Int: PageReading] = [:]
    /// The model is reading a recipe that fell short.
    private(set) var refining: String?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// The book was deleted: nothing more is written for it.
    @ObservationIgnored private var isAbandoned = false
    @ObservationIgnored private var lens = LensWatch()
    @ObservationIgnored private let images = ScanSaving.PageImages()
    private static let logger = Logger(subsystem: "com.calebpietrafesa.RecipeCodex", category: "scan")

    init(book: Book, context: ModelContext) {
        self.book = book
        bookID = book.id
        self.context = context
        state = BookScanState.load(bookID: book.id) ?? BookScanState()
    }

    var folder: URL { BookScanState.folder(for: bookID) }

    private func url(of capture: BookScanState.StoredCapture) -> URL {
        folder.appending(path: capture.file)
    }

    private func save() {
        guard !isAbandoned else { return }
        state.save(bookID: bookID)
    }

    // MARK: - Opening and pausing

    /// Opens a sitting: earlier sittings' finished captures let go, the current item set (Scan now
    /// passes its entry), the queue started.
    func open(at entry: BookEntry? = nil) {
        book.reconcilePunchlist()
        if !isOpen {
            state.sitting += 1
            let sitting = state.sitting
            for capture in state.captures where capture.status != .pending && capture.sitting < sitting {
                try? FileManager.default.removeItem(at: url(of: capture))
            }
            state.captures.removeAll { $0.status != .pending && $0.sitting < sitting }
            readings = [:]
            lastCapturePreview = []
            lens.reset()
        }
        isOpen = true
        if let entry {
            state.currentEntry = entry.id
        } else if currentEntry == nil || currentEntry?.status != .listed {
            moveToNextUncaptured(after: currentEntry)
        }
        save()
        kick()
    }

    /// Close: nothing is lost. Captures still reading finish in the queue.
    func pause() {
        isOpen = false
        save()
        kick()
    }

    // MARK: - The current item

    var currentEntry: BookEntry? {
        state.currentEntry.flatMap { id in book.orderedEntries.first { $0.id == id } }
    }

    /// Tap to jump (03 §3.8).
    func select(_ entry: BookEntry) {
        state.currentEntry = entry.id
        save()
    }

    private func moveToNextUncaptured(after entry: BookEntry?) {
        let entries = book.orderedEntries
        let index = entry.flatMap { entries.firstIndex(of: $0) }
        state.currentEntry = PunchlistMatcher.next(after: index, in: book.matcherEntries).map { entries[$0].id }
    }

    // MARK: - Counts, for the status strip

    /// This sitting's captures, and any left waiting from before.
    var shownCaptures: [BookScanState.StoredCapture] {
        state.captures.filter { $0.sitting == state.sitting || $0.status == .pending }
    }

    var capturedCount: Int { shownCaptures.count }
    var processedCount: Int { shownCaptures.count { $0.status != .pending } }
    var needReviewCount: Int { book.reviewQueue.count }
    var isReadingCaptures: Bool { state.captures.contains { $0.status == .pending } }

    /// The last capture this sitting, for its pane and the Needs Review toggle.
    var lastCapture: BookScanState.StoredCapture? {
        state.captures.filter { $0.sitting == state.sitting }.max { $0.id < $1.id }
    }

    /// Whether the last capture's recipes are in the review queue. A page joined to the one before
    /// has its recipes on that capture, so its answer is that capture's.
    func needsReview(_ capture: BookScanState.StoredCapture) -> Bool {
        if let flagged = capture.flagged { return flagged }
        let owner = capture.joinedTo.flatMap { id in state.captures.first { $0.id == id } } ?? capture
        return owner.flagged ?? owner.queued
    }

    /// The Needs Review toggle (03 §3.8): the capture's recipes join or leave the review queue.
    func setNeedsReview(_ on: Bool, for id: Int) {
        guard let index = state.captures.firstIndex(where: { $0.id == id }) else { return }
        state.captures[index].flagged = on
        let owner = state.captures[index].joinedTo.flatMap { joined in state.captures.firstIndex { $0.id == joined } } ?? index
        if state.captures[owner].status == .processed {
            for recipe in recipes(of: state.captures[owner]) { recipe.currentVersion?.needsReview = on }
            state.captures[owner].queued = on
            try? context.save()
        }
        save()
    }

    // MARK: - Courses

    /// The course a chapter's recipes are saved with (ux-notes row 73).
    func course(for section: BookSection) -> String? {
        section.course(choices: state.courses)
    }

    /// Confirmed or changed inline on the punchlist; recipes saved from now on take it.
    func setCourse(_ course: String?, for section: BookSection) {
        state.courses[section.id] = course ?? ""
        save()
    }

    // MARK: - The camera's sink

    var namesBookByBarcode: Bool { false }

    func captureFolder() -> URL {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func reserveCaptureID() -> Int {
        defer { state.nextCaptureID += 1 }
        return state.nextCaptureID
    }

    var captureItems: [CaptureItem] {
        shownCaptures.map { capture in
            CaptureItem(id: capture.id, url: url(of: capture), mode: capture.mode, note: capture.note,
                        detail: capture.status == .pending ? "Reading…" : capture.detail,
                        needsReview: capture.mode == .recipe && !capture.recipes.isEmpty ? needsReview(capture) : nil)
        }
    }

    func addCapture(id: Int, at url: URL, mode: CaptureMode, quality: PageQualityReading?, note: String) {
        addCapture(id: id, at: url, mode: mode, quality: quality, note: note, entry: state.currentEntry)
    }

    private func addCapture(id: Int, at url: URL, mode: CaptureMode, quality: PageQualityReading?, note: String, entry: UUID?) {
        var capture = BookScanState.StoredCapture(id: id, file: url.lastPathComponent, mode: mode, quality: quality.map(BookScanState.Quality.init), note: note)
        capture.entry = entry
        capture.sitting = state.sitting
        state.captures.append(capture)
        save()
        kick()
    }

    func shelfBook(isbn: String) -> Book? { book.isbn == isbn ? book : nil }

    /// Deleting a capture removes it from the queue and the scan (ux-notes row 83): what it saved
    /// goes, its entries back to listed; a page joined to the one before leaves that page to be
    /// read again on its own.
    func removeCapture(id: Int) {
        guard let index = state.captures.firstIndex(where: { $0.id == id }) else { return }
        let capture = state.captures[index]
        undo(capture)
        // Pages joined to it are read again on their own; the page it joined is read again
        // without it, with the other pages joined to that one.
        resetToPending(index)
        if let owner = capture.joinedTo, let ownerIndex = state.captures.firstIndex(where: { $0.id == owner }) {
            undo(state.captures[ownerIndex])
            resetToPending(ownerIndex)
        }
        try? FileManager.default.removeItem(at: url(of: capture))
        state.captures.removeAll { $0.id == id }
        readings[id] = nil
        try? context.save()
        save()
        kick()
    }

    /// A capture made a recipe page or a photo after the fact: what it saved goes and it is read
    /// again as what it now is.
    func setMode(_ mode: CaptureMode, ofCapture id: Int) {
        guard let index = state.captures.firstIndex(where: { $0.id == id }), state.captures[index].mode != mode else { return }
        undo(state.captures[index])
        if let owner = state.captures[index].joinedTo, let ownerIndex = state.captures.firstIndex(where: { $0.id == owner }) {
            undo(state.captures[ownerIndex])
            resetToPending(ownerIndex)
        }
        state.captures[index].mode = mode
        resetToPending(index)
        try? context.save()
        save()
        kick()
    }

    /// A capture to be read again, and with it every page joined to it: a page that continued it
    /// was saved into its recipe, which is gone, so that page is read again too and joins again
    /// once the first is saved.
    private func resetToPending(_ index: Int) {
        let id = state.captures[index].id
        for reset in state.captures.indices where reset == index || state.captures[reset].joinedTo == id {
            state.captures[reset].status = .pending
            state.captures[reset].recipes = []
            state.captures[reset].photo = nil
            state.captures[reset].detail = nil
            state.captures[reset].queued = false
            state.captures[reset].joinedTo = nil
            state.captures[reset].photographPages = []
        }
    }

    /// Takes back what a processed capture saved.
    private func undo(_ capture: BookScanState.StoredCapture) {
        for recipe in recipes(of: capture) {
            if let entry = recipe.bookEntry { entry.status = .listed }
            context.delete(recipe)
        }
        if let photoID = capture.photo,
           let image = try? context.fetch(FetchDescriptor<RecipeImage>(predicate: #Predicate { $0.id == photoID })).first {
            if image.caption == "Cover" { image.recipe?.coverImageData = nil }
            context.delete(image)
        }
    }

    private func recipes(of capture: BookScanState.StoredCapture) -> [Recipe] {
        capture.recipes.compactMap { id in try? context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })).first }
    }

    // MARK: - From Photo and Files (the Simulator, which has no camera)

    /// Photos chosen in Photos, in the order chosen, as captures.
    func add(photos items: [PhotosPickerItem], mode: CaptureMode) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            add(data, extension: item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg", mode: mode)
        }
    }

    /// Image files chosen in Files, as captures.
    func add(files urls: [URL], mode: CaptureMode) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            add(data, extension: url.pathExtension.isEmpty ? "jpg" : url.pathExtension, mode: mode)
        }
    }

    private func add(_ data: Data, extension pathExtension: String, mode: CaptureMode) {
        let id = reserveCaptureID()
        let url = captureFolder().appending(path: "capture-\(id + 1).\(pathExtension)")
        guard (try? data.write(to: url)) != nil else { return }
        let number = shownCaptures.count + 1
        addCapture(id: id, at: url, mode: mode, quality: nil, note: "\(mode == .photo ? "Photo" : "Page") \(number)", entry: nil)
    }

    // MARK: - The queue

    /// Starts the queue if it isn't running.
    func kick() {
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    /// Reads and saves every waiting capture in capture order. What a background task would call.
    /// Stops when its task is cancelled (the book was deleted).
    func drain() async {
        while !Task.isCancelled, let next = state.captures.filter({ $0.status == .pending }).map(\.id).min() {
            await process(next)
        }
        worker = nil
    }

    /// The book is gone: nothing more is read or written for it.
    func abandon() {
        isAbandoned = true
        worker?.cancel()
    }

    private var pipeline: PagePipeline { ScanSession.makePipeline() }

    private func process(_ id: Int) async {
        guard let index = state.captures.firstIndex(where: { $0.id == id }) else { return }
        let capture = state.captures[index]
        let url = url(of: capture)
        let pipeline = pipeline
        let read = try? await Self.read(url, quality: capture.quality?.reading, with: pipeline)
        // The book was deleted while it was read: nothing is saved for it.
        guard !isAbandoned else { return }
        guard let reading = read else {
            finish(id) { $0.status = .failed; $0.detail = "Couldn't be read" }
            return
        }
        // Deleted or made a photo while it was read: as it is now.
        guard let now = state.captures.first(where: { $0.id == id && $0.status == .pending }) else { return }
        readings[id] = reading
        if now.mode == .recipe, reading.kind == .recipe {
            lastCapturePreview = reading.previewBlocks
            if lens.note(reading, quality: capture.quality?.reading) { asksToCleanLens = true }
        }
        if now.mode == .photo || reading.kind == .photo {
            await attachPhoto(id, reading: reading)
        } else if reading.kind == .recipe, !reading.recipes.isEmpty {
            await saveRecipes(id, reading: reading)
        } else {
            await keep(id, reading: reading)
        }
        // Never left waiting, or the queue would read it again.
        if state.captures.contains(where: { $0.id == id && $0.status == .pending }) {
            finish(id) { $0.status = .failed; $0.detail = "Couldn't be saved" }
        }
        try? context.save()
        save()
    }

    static let waitingDetail = "Waiting for its recipe"

    /// Records what became of a capture.
    private func finish(_ id: Int, _ change: (inout BookScanState.StoredCapture) -> Void) {
        guard let index = state.captures.firstIndex(where: { $0.id == id }) else { return }
        change(&state.captures[index])
        if state.captures[index].status == .pending { state.captures[index].status = .processed }
        // Finished after Close: the next sitting shows it, so the cook sees what became of it.
        if !isOpen { state.captures[index].sitting = state.sitting + 1 }
        save()
    }

    @concurrent
    nonisolated private static func read(_ url: URL, quality: PageQualityReading?, with pipeline: PagePipeline) async throws -> PageReading {
        try await pipeline.readPage(contentsOf: url, page: 0, of: 1, quality: quality)
    }

    @concurrent
    nonisolated private static func refine(_ readings: [PageReading], urls: [URL], with pipeline: PagePipeline) async -> [PageReading] {
        await pipeline.finish(readings, urls: urls)
    }

    /// A recipe page: joined to the page before when it continues it, refined by the model where
    /// it falls short, every recipe on it saved and matched to its entry.
    private func saveRecipes(_ id: Int, reading single: PageReading) async {
        guard let index = state.captures.firstIndex(where: { $0.id == id }) else { return }
        var owner = id
        var urls = [url(of: state.captures[index])]
        var parts = [single]
        // A page that opens mid-recipe continues the page captured before it: that page and every
        // page already joined to it, in order, so a recipe over three pages keeps its middle. The
        // stitcher decides, as it will when the pages are refined together.
        if single.isContinuation, let previous = previousRecipeCapture(before: id) {
            let chain = [previous] + state.captures.filter { $0.joinedTo == previous.id }.sorted { $0.id < $1.id }
            let earlier = chain.compactMap { readings[$0.id] }
            if earlier.count == chain.count, PageStitcher.stitch(earlier + [single]).count == 1 {
                undo(previous)
                owner = previous.id
                urls = chain.map(url(of:)) + urls
                parts = earlier + parts
                state.captures[index].joinedTo = previous.id
            }
        }
        if parts.contains(where: { $0.recipes.contains(where: PagePipeline.wantsModel) }) {
            refining = single.recipes.first?.title ?? ""
        }
        let reading = await Self.refine(parts, urls: urls, with: pipeline).first ?? single
        refining = nil
        guard !isAbandoned, let ownerIndex = state.captures.firstIndex(where: { $0.id == owner }) else { return }
        let ownerCapture = state.captures[ownerIndex]
        // Needs Review as the cook set it on this capture (the last capture's pane shows this one,
        // joined or not), else on the page it joined.
        let flagged = state.captures.first { $0.id == id }?.flagged ?? ownerCapture.flagged

        let model = ScanReviewModel(reading: reading, urls: urls)
        // A first recipe that continues a page nobody captured: nothing to join it to.
        if reading.isContinuation, owner == id { model.recipes[0].isSkipped = true }
        let titles = model.recipes.map { $0.title?.text ?? "" }
        let pages = PunchlistMatcher.pages(read: reading.pageNumbers)
        // A camera capture is the item that was current when it was taken; photos chosen in a batch
        // follow the list as each is read.
        let current = ownerCapture.entry.flatMap { entryID in book.orderedEntries.first { $0.id == entryID } } ?? currentEntry
        let match = PunchlistLinking.match(titles: titles, pages: pages, in: book, current: current, courses: state.courses, context: context)

        var hasRecipes = !(book.recipes ?? []).isEmpty
        var layouts = Set(book.reviewedLayouts + state.layouts)
        var saved: [Recipe] = []
        var linked: [BookEntry] = []
        var again: [String] = []
        var queued = false
        for recipeIndex in model.recipes.indices where !model.recipes[recipeIndex].isSkipped {
            let entry = match.entries[recipeIndex]
            // The punchlist names a recipe the page's title didn't read for.
            if model.recipes[recipeIndex].title?.text.trimmed.isEmpty != false {
                let name = entry.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Recipe"
                model.recipes[recipeIndex].title = ReviewItem(text: name, regions: model.recipes[recipeIndex].title?.regions ?? [])
            }
            let read = reading.recipes[recipeIndex]
            let reasons = read.reviewReasons(bookHasRecipes: hasRecipes, reviewedLayouts: layouts)
            model.recipes[recipeIndex].reasons = reasons
            model.recipes[recipeIndex].course = match.courses[recipeIndex]
            // A recipe saved again over a page join that was in the queue stays there: the book's
            // first recipe and its layout were counted when it was first saved.
            let wantsLook = flagged ?? (!reasons.isEmpty || read.title.isEmpty || ownerCapture.queued)
            let recipe = await ScanSaving.saveNew(model, recipe: recipeIndex, book: book, reviewed: false, images: images, in: context)
            recipe.currentVersion?.needsReview = wantsLook
            if PunchlistLinking.link(recipe, to: entry, reviewed: false), let entry {
                linked.append(entry)
            } else if entry != nil {
                // A page shot again: saved, nothing lost, the list left as it is.
                again.append(recipe.title)
            }
            hasRecipes = true
            if !read.layoutSignature.isEmpty, !layouts.contains(read.layoutSignature) {
                layouts.insert(read.layoutSignature)
                state.layouts.append(read.layoutSignature)
            }
            queued = queued || wantsLook
            saved.append(recipe)
        }
        try? context.save()

        let photographs = reading.recipes.flatMap(\.crossReferences).filter { $0.kind == .photograph }.flatMap(\.pages)
        finish(owner) { capture in
            capture.recipes = saved.map(\.id)
            capture.queued = queued
            capture.pageNumber = pages.first
            capture.photographPages = photographs
            capture.detail = Self.savedLine(saved, skipped: model.recipes.first?.isSkipped == true && saved.isEmpty)
                + (again.isEmpty ? "" : " · already captured, saved again")
        }
        if owner != id { finish(id) { $0.detail = "Continues the page before" } }

        // Photos waiting for a recipe go with the first one saved.
        for waiting in state.captures where waiting.detail == Self.waitingDetail && waiting.photo == nil && waiting.id < id {
            if let recipe = saved.first { await attach(waiting.id, to: recipe) }
        }
        // Photos that went with a recipe saved again over a page join go with it again.
        for orphan in state.captures where orphan.photo != nil && !imageExists(orphan.photo!) {
            if let recipe = saved.last { await attach(orphan.id, to: recipe) }
        }
        // The list moves on, unless the cook jumped elsewhere since this page was taken, or the page
        // was one already captured.
        let matched = linked
        if ownerCapture.entry == nil || state.currentEntry == ownerCapture.entry || matched.contains(where: { $0.id == state.currentEntry }) || state.currentEntry == nil {
            let entries = book.orderedEntries
            let last = matched.compactMap { entries.firstIndex(of: $0) }.max()
            if let last {
                state.currentEntry = PunchlistMatcher.next(after: last, in: book.matcherEntries).map { entries[$0].id }
            } else if currentEntry?.status != .listed {
                moveToNextUncaptured(after: currentEntry)
            }
        }
        Self.logger.info("Book session: capture \(id) saved \(saved.count) recipes, \(matched.count) on the list\(queued ? ", queued for review" : "")")
    }

    /// "Saved “Leek Soup” and “Bean Soup”", "Saved “Leek Soup” (not on the list)".
    private static func savedLine(_ recipes: [Recipe], skipped: Bool) -> String {
        if recipes.isEmpty { return skipped ? "Continues a page not captured" : "Nothing saved" }
        let titles = recipes.map { "“\($0.title)”" }
        return "Saved " + (titles.count > 2 ? titles.prefix(2).joined(separator: ", ") + " and \(titles.count - 2) more" : titles.joined(separator: " and "))
    }

    private func imageExists(_ id: UUID) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<RecipeImage>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
    }

    /// The recipe capture before `id` in capture order.
    private func previousRecipeCapture(before id: Int) -> BookScanState.StoredCapture? {
        state.captures.filter { $0.id < id && $0.mode == .recipe && $0.status == .processed && $0.joinedTo == nil && !$0.recipes.isEmpty }.max { $0.id < $1.id }
    }

    /// A Photo capture, or a page that reads as a photo plate: a cover candidate for the recipe that
    /// points to its page ("photograph on page 12"), or else the recipe before it, or, when none
    /// came before, the next one saved (04 §5.1 "Printed photos").
    private func attachPhoto(_ id: Int, reading: PageReading) async {
        let page = reading.pageNumber
        let earlier = state.captures.filter { $0.id < id && !$0.recipes.isEmpty }
        let target = page.flatMap { page in earlier.last { $0.photographPages.contains(page) } } ?? earlier.last
        finish(id) { $0.pageNumber = page; $0.detail = Self.waitingDetail }
        if let target, let recipe = recipes(of: target).last {
            await attach(id, to: recipe)
        }
    }

    private func attach(_ id: Int, to recipe: Recipe) async {
        guard let capture = state.captures.first(where: { $0.id == id }) else { return }
        let attached = await ScanSaving.attachCoverCandidates([url(of: capture)], to: recipe, in: context)
        finish(id) { $0.photo = attached.first?.id; $0.detail = "A cover for “\(recipe.title)”" }
    }

    /// A page that is no recipe: a contents, index or Sources page or prose is kept on the book as a
    /// page scan; a blank or unreadable one is let go.
    private func keep(_ id: Int, reading: PageReading) async {
        guard let capture = state.captures.first(where: { $0.id == id }) else { return }
        switch reading.kind {
        case .contents, .index, .sources, .prose:
            let model = ScanReviewModel(reading: reading, urls: [url(of: capture)])
            await ScanSaving.keepPageScan(model, kind: reading.kind, book: book, images: images, in: context)
            finish(id) { $0.pageNumber = reading.pageNumber; $0.detail = "\(reading.kind.title), kept with the book" }
        default:
            finish(id) { $0.detail = "\(reading.kind.title): not kept" }
        }
    }
}

/// The book sessions alive in the app: a session outlives its view, so Close pauses while its queue
/// finishes, and Continue Scanning finds it again. At launch, sessions with captures left waiting
/// resume.
@MainActor
final class BookScanStore {
    static let shared = BookScanStore()

    private var sessions: [UUID: BookScanSession] = [:]

    func session(for book: Book, context: ModelContext) -> BookScanSession {
        if let session = sessions[book.id] { return session }
        let session = BookScanSession(book: book, context: context)
        sessions[book.id] = session
        return session
    }

    /// The courses chosen per chapter in the book's sessions.
    func courseChoices(for book: Book) -> [UUID: String] {
        sessions[book.id]?.state.courses ?? BookScanState.load(bookID: book.id)?.courses ?? [:]
    }

    /// Whether the book has a session to continue: captures, or a current item.
    func hasSession(for book: Book) -> Bool {
        sessions[book.id] != nil || BookScanState.load(bookID: book.id) != nil
    }

    /// Relaunch: every book whose session left captures waiting reads them now. A folder whose
    /// book the store doesn't hold is left alone: the store may be the in-memory fallback.
    func resume(in context: ModelContext) {
        for id in BookScanState.booksWithPendingCaptures() where sessions[id] == nil {
            guard let book = try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first else { continue }
            session(for: book, context: context).kick()
        }
    }

    /// The book is being deleted: its session stops, and its captures and state go with it.
    func forget(bookID: UUID) {
        sessions[bookID]?.abandon()
        sessions[bookID] = nil
        try? FileManager.default.removeItem(at: BookScanState.folder(for: bookID))
    }
}
