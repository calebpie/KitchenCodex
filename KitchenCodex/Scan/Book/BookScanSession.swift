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
/// lost, captures still reading finish, a relaunch resumes them (`BookScanStore.resume`), and the
/// background task drains them while the app is away (`BookScanBackground`, ux-notes row 92).
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
    private static let logger = Logger(subsystem: "com.calebpietrafesa.KitchenCodex", category: "scan")

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

    /// A change to the state from outside the queue (the cross-reference card, Scan page N), kept.
    func updateState(_ change: (inout BookScanState) -> Void) {
        change(&state)
        save()
    }

    // MARK: - Opening and pausing

    /// Opens a sitting: earlier sittings' finished captures let go but for the last recipe capture
    /// (and the pages joined to it), so this sitting's first page can continue it, and the photos
    /// still waiting for a recipe (ux-notes row 98); the current item set (Scan now passes its
    /// entry), the queue started.
    func open(at entry: BookEntry? = nil) {
        book.reconcilePunchlist()
        CrossReferenceLinking.prune(in: book, state: &state, context: context)
        if !isOpen {
            state.sitting += 1
            let sitting = state.sitting
            let carried = carriedCaptures()
            for capture in state.captures where capture.status != .pending && capture.sitting < sitting && !carried.contains(capture.id) {
                try? FileManager.default.removeItem(at: url(of: capture))
            }
            state.captures.removeAll { $0.status != .pending && $0.sitting < sitting && !carried.contains($0.id) }
            // Readings are read again from the files when a page needs them (`readings(of:)`).
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

    /// What a new sitting keeps from the ones before: the last recipe capture with recipes and the
    /// pages joined to it, and every photo still waiting for its recipe.
    private func carriedCaptures() -> Set<Int> {
        var kept = Set(state.captures.filter { $0.detail == Self.waitingDetail && $0.photo == nil }.map(\.id))
        if let last = previousRecipeCapture(before: .max) {
            kept.insert(last.id)
            kept.formUnion(state.captures.filter { $0.joinedTo == last.id }.map(\.id))
        }
        return kept
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
    var needReviewCount: Int { book.reviewQueue.count + ReferenceSaving.reviewQueue(for: book).count }
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
            // A reference waits in the queue through the capture's own flag.
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
                        needsReview: capture.mode == .recipe && (!capture.recipes.isEmpty || !capture.references.isEmpty) ? needsReview(capture) : nil,
                        keepWhich: capture.duplicates.isEmpty ? nil : keepQuestion(capture),
                        joinWhich: capture.joinOffer.map { "This page continues “\($0.title)”, which was reviewed or edited since. Join it, reading the recipe again as a new version, or keep it apart?" },
                        contentsWhich: capture.contentsOffer ? "This looks like a contents page, not a recipe page." : nil)
        }
    }

    func addCapture(id: Int, at url: URL, mode: CaptureMode, quality: PageQualityReading?, note: String) {
        addCapture(id: id, at: url, mode: mode, quality: quality, note: note, entry: state.currentEntry)
    }

    /// "“Leek Soup” is already captured, and was reviewed or edited since. Keep which?"
    private func keepQuestion(_ capture: BookScanState.StoredCapture) -> String {
        let titles = capture.duplicates.map(\.earlier).compactMap { earlier in
            try? context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == earlier })).first?.title
        }
        let named = titles.count == 1 ? "“\(titles[0])” is" : "These recipes are"
        return "\(named) already captured and was reviewed or edited since. Keep which?"
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
            state.captures[reset].duplicates = []
            state.captures[reset].references = []
            state.captures[reset].sources = []
            state.captures[reset].joinOffer = nil
        }
    }

    /// Takes back what a processed capture saved: its recipes, the entries made for them because
    /// the list lacked them (the Oct 21 review's finding 8), their places on entries their
    /// pointers put on the list, and the references and suppliers read from it.
    private func undo(_ capture: BookScanState.StoredCapture) {
        let created = Set(capture.createdEntries)
        for recipe in recipes(of: capture) {
            if let entry = recipe.bookEntry { entry.status = .listed }
            context.delete(recipe)
        }
        for id in capture.references {
            if let reference = try? context.fetch(FetchDescriptor<Reference>(predicate: #Predicate { $0.id == id })).first {
                ReferenceSaving.delete(reference, in: context)
            }
        }
        for id in capture.sources {
            if let source = try? context.fetch(FetchDescriptor<Source>(predicate: #Predicate { $0.id == id })).first {
                context.delete(source)
            }
        }
        // A Sources page taken back takes its page scan with it.
        if !capture.sources.isEmpty {
            for scan in book.sourcesPages where scan.pageNumber == capture.pageNumber { context.delete(scan) }
        }
        for entry in book.orderedEntries where created.contains(entry.id) && entry.reference == nil {
            context.delete(entry)
        }
        if let index = state.captures.firstIndex(where: { $0.id == capture.id }) { state.captures[index].createdEntries = [] }
        CrossReferenceLinking.forget(recipes: Set(capture.recipes), in: book, state: &state, context: context)
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

    /// Runs the queue to its end: the worker already reading, or a new one. The background task's
    /// way in, so a drain never runs beside another.
    func runQueue() async {
        kick()
        await worker?.value
    }

    /// The background task's time is up: the worker stops after the capture in hand.
    func stopWorker() {
        worker?.cancel()
    }

    /// Reads and saves every waiting capture in capture order. Stops when its task is cancelled (the
    /// book was deleted, or the background task's time ran out).
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
        // Stopped mid-read (the background task's time ran out): it waits for the next chance.
        if read == nil, Task.isCancelled { return }
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
        } else if ContentsReader.judge(reading) == .contents {
            // A contents page shot here: said so, and offered to the list (ux-notes row 114).
            finish(id) { $0.pageNumber = reading.pageNumber; $0.contentsOffer = true; $0.detail = "Looks like a contents page, not a recipe page" }
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
        var joinOffer: BookScanState.JoinOffer?
        if single.isContinuation, let previous = previousRecipeCapture(before: id) {
            let chain = [previous] + state.captures.filter { $0.joinedTo == previous.id }.sorted { $0.id < $1.id }
            // A page from an earlier sitting, or read before a relaunch, is read again from its file
            // (ux-notes row 98).
            let earlier = await readings(of: chain)
            let cooksWork = recipes(of: previous).first { !Self.isUntouched($0) }
            if let cooksWork {
                // Joining would read the recipe again over what the cook did to it: the page saves
                // on its own and the captures sheet asks Join · Keep Apart (ux-notes row 100).
                joinOffer = BookScanState.JoinOffer(previous: previous.id, recipe: cooksWork.id, title: cooksWork.title)
            } else if earlier.count == chain.count, PageStitcher.stitch(earlier + [single]).count == 1 {
                undo(previous)
                owner = previous.id
                urls = chain.map(url(of:)) + urls
                parts = earlier + parts
                state.captures[index].joinedTo = previous.id
                // An owner carried from an earlier sitting shows in this one again.
                if let ownerIndex = state.captures.firstIndex(where: { $0.id == previous.id }) { state.captures[ownerIndex].sitting = state.sitting }
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
        let match = PunchlistLinking.match(titles: titles, pages: pages, in: book, current: current, courses: state.courses, growsList: true, context: context)

        var hasRecipes = !(book.recipes ?? []).isEmpty
        var layouts = Set(book.reviewedLayouts + state.layouts)
        var saved: [Recipe] = []
        var linked: [BookEntry] = []
        var replaced = 0
        var duplicates: [BookScanState.Duplicate] = []
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
            let recipe = await ScanSaving.saveNew(model, recipe: recipeIndex, book: book, reviewed: false, images: images, appliesPointers: false, in: context)
            recipe.currentVersion?.needsReview = wantsLook
            if PunchlistLinking.link(recipe, to: entry, reviewed: false), let entry {
                linked.append(entry)
            } else if let entry, let earlier = entry.recipe, earlier != recipe {
                // A page shot again (ux-notes row 93): it replaces a recipe the cook hasn't reviewed
                // or edited since it was saved; otherwise both stay until the captures sheet asks.
                if Self.isUntouched(earlier) {
                    replace(earlier, with: recipe, on: entry)
                    linked.append(entry)
                    replaced += 1
                } else {
                    duplicates.append(BookScanState.Duplicate(new: recipe.id, earlier: earlier.id, entry: entry.id))
                }
            }
            hasRecipes = true
            if !read.layoutSignature.isEmpty, !layouts.contains(read.layoutSignature) {
                layouts.insert(read.layoutSignature)
                state.layouts.append(read.layoutSignature)
            }
            queued = queued || wantsLook
            saved.append(recipe)
        }
        // Cross-references without a card (02 Flow C step 6): pointers to these pages link their
        // recipes to the ones just saved; these recipes' own pointers link to a recipe the book has
        // from that page, or put the page on the to-scan list. After the whole page, so "recipe
        // follows" finds the recipe printed after it.
        for (recipe, recipeIndex) in zip(saved, model.recipes.indices.filter { !model.recipes[$0].isSkipped }) {
            CrossReferenceLinking.linkWaiting(to: recipe, pages: pages.isEmpty ? [recipe.pageNumber].compactMap(\.self) : pages, in: book, state: &state, context: context)
            CrossReferenceLinking.applySessionRule(reading.recipes[recipeIndex].crossReferences, for: recipe, in: book, state: &state, context: context)
        }
        try? context.save()

        let photographs = reading.recipes.flatMap(\.crossReferences).filter { $0.kind == .photograph }.flatMap(\.pages)
        finish(owner) { capture in
            capture.recipes = saved.map(\.id)
            capture.createdEntries = match.created.map(\.id)
            capture.queued = queued
            capture.pageNumber = pages.first
            capture.photographPages = photographs
            capture.duplicates = duplicates
            capture.joinOffer = joinOffer
            let continues = joinOffer.map { "continues “\($0.title)”, which was reviewed or edited since" }
            if let continues, saved.isEmpty {
                capture.detail = continues.prefix(1).uppercased() + continues.dropFirst()
            } else {
                capture.detail = Self.savedLine(saved, skipped: model.recipes.first?.isSkipped == true && saved.isEmpty)
                    + (replaced == 0 ? "" : replaced == 1 ? " · replaced the earlier copy" : " · replaced the earlier copies")
                    + (duplicates.isEmpty ? "" : " · already captured")
                    + (continues.map { " · \($0)" } ?? "")
            }
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

    // MARK: - A page shot again (ux-notes row 93)

    /// Neither reviewed nor edited since the scan saved it, by what the library records: no review
    /// (Review Scan, the queue, Looks Right), one version, and no change after its save (an edit, a
    /// past cook added).
    static func isUntouched(_ recipe: Recipe) -> Bool {
        recipe.source?.reviewedAt == nil && recipe.bookEntry?.status != .reviewed
            && (recipe.versions?.count ?? 0) <= 1 && recipe.updatedAt.timeIntervalSince(recipe.createdAt) < 5
    }

    /// `new` takes `earlier`'s place: its entry, its cover photos and cover, the links that name
    /// it as a component and the ones it holds as a parent (its Includes, ux-notes row 105), and
    /// its related reading; `earlier` goes, and so does its place on the capture that saved it.
    private func replace(_ earlier: Recipe, with new: Recipe, on entry: BookEntry) {
        for image in earlier.images ?? [] where image.role == .photo {
            image.recipe = new
        }
        if new.coverImageData == nil { new.coverImageData = earlier.coverImageData }
        for link in earlier.linkedFrom ?? [] { link.subRecipe = new }
        for link in earlier.links ?? [] {
            if let component = link.subRecipe, (new.links ?? []).contains(where: { $0.role == link.role && $0.subRecipe == component }) {
                context.delete(link)
            } else {
                link.parent = new
            }
        }
        for reference in earlier.references ?? [] where !(new.references ?? []).contains(reference) {
            new.references = (new.references ?? []) + [reference]
        }
        for index in state.captures.indices where state.captures[index].recipes.contains(earlier.id) {
            state.captures[index].recipes.removeAll { $0 == earlier.id }
        }
        // The new copy points where the earlier did: it takes the earlier's place on the pointer
        // entries, so a page captured later links it (ux-notes row 105).
        for index in state.pointerEntries.indices where state.pointerEntries[index].recipes.contains(earlier.id) {
            state.pointerEntries[index].recipes.removeAll { $0 == earlier.id }
            if !state.pointerEntries[index].recipes.contains(new.id) { state.pointerEntries[index].recipes.append(new.id) }
        }
        earlier.bookEntry = nil
        context.delete(earlier)
        PunchlistLinking.link(new, to: entry, reviewed: false)
    }

    /// The captures sheet's answer: Keep New replaces the earlier recipes as an untouched one would
    /// be; Keep Earlier deletes the new ones. Until then nothing is deleted. The kept copy's
    /// pointers are linked again either way (ux-notes row 105): the recipes pointing at its pages
    /// link to it, and its own pointers to the pages the book holds.
    func resolveDuplicates(of id: Int, keepNew: Bool) {
        guard let index = state.captures.firstIndex(where: { $0.id == id }) else { return }
        let fetch = { (id: UUID) in try? self.context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })).first }
        var kept: [Recipe] = []
        for duplicate in state.captures[index].duplicates {
            guard let new = fetch(duplicate.new) else { continue }
            if keepNew {
                if let earlier = fetch(duplicate.earlier), let entry = book.orderedEntries.first(where: { $0.id == duplicate.entry }) {
                    replace(earlier, with: new, on: entry)
                }
                kept.append(new)
            } else {
                CrossReferenceLinking.forget(recipes: [new.id], in: book, state: &state, context: context)
                context.delete(new)
                if let current = state.captures.firstIndex(where: { $0.id == id }) { state.captures[current].recipes.removeAll { $0 == duplicate.new } }
                if let earlier = fetch(duplicate.earlier) { kept.append(earlier) }
            }
        }
        for recipe in kept {
            let pages = Array(CrossReferenceLinking.ownPages(of: recipe)).sorted()
            CrossReferenceLinking.linkWaiting(to: recipe, pages: pages, in: book, state: &state, context: context)
            CrossReferenceLinking.applySessionRule(CrossReferenceLinking.pointers(of: recipe), for: recipe, in: book, state: &state, context: context)
        }
        if let current = state.captures.firstIndex(where: { $0.id == id }) {
            state.captures[current].duplicates = []
            let detail = state.captures[current].detail?.replacingOccurrences(of: " · already captured", with: "") ?? ""
            state.captures[current].detail = detail + (keepNew ? " · replaced the earlier copy" : " · kept the earlier copy")
        }
        try? context.save()
        save()
    }

    // MARK: - A page continuing a reviewed recipe (ux-notes row 100)

    /// The captures sheet's answer. Keep Apart leaves the page saved on its own. Join reads the
    /// recipe again with this page: the page it continues and every page joined to it, read as
    /// one with this one, and saved as a new version of each recipe the page before held (the
    /// cook's review stays as history); this page's own recipes go, and it joins the page before.
    func resolveJoin(of id: Int, join: Bool) {
        guard let index = state.captures.firstIndex(where: { $0.id == id }), let offer = state.captures[index].joinOffer else { return }
        state.captures[index].joinOffer = nil
        let detail = state.captures[index].detail?.replacingOccurrences(of: ", which was reviewed or edited since", with: "") ?? ""
        guard join else {
            state.captures[index].detail = detail + ": kept apart"
            save()
            return
        }
        state.captures[index].detail = detail + ": joining…"
        save()
        Task { await self.join(id, offer: offer) }
    }

    private func join(_ id: Int, offer: BookScanState.JoinOffer) async {
        guard let index = state.captures.firstIndex(where: { $0.id == id }),
              let previous = state.captures.first(where: { $0.id == offer.previous }) else { return }
        let chain = [previous] + state.captures.filter { $0.joinedTo == previous.id }.sorted { $0.id < $1.id }
        let earlier = await readings(of: chain)
        let own = await readings(of: [state.captures[index]])
        guard earlier.count == chain.count, let single = own.first else { return }
        let stitched = PageStitcher.stitch(earlier + [single])
        guard stitched.count == 1, !isAbandoned else {
            finish(id) { $0.detail = ($0.detail ?? "").replacingOccurrences(of: ": joining…", with: ": kept apart (the pages don't read as one)") }
            return
        }
        // This page's own recipes go; the page before keeps its recipes, read again.
        undo(state.captures[index])
        if let current = state.captures.firstIndex(where: { $0.id == id }) {
            state.captures[current].recipes = []
            state.captures[current].createdEntries = []
            state.captures[current].joinedTo = previous.id
        }
        let urls = chain.map(url(of:)) + [url(of: state.captures[index])]
        refining = single.recipes.first?.title ?? ""
        let reading = await Self.refine(stitched, urls: urls, with: pipeline).first ?? stitched[0]
        refining = nil
        guard !isAbandoned else { return }
        let model = ScanReviewModel(reading: reading, urls: urls)
        let existing = recipes(of: previous)
        var saved: [Recipe] = []
        for recipeIndex in model.recipes.indices {
            if existing.indices.contains(recipeIndex) {
                let recipe = existing[recipeIndex]
                await ScanSaving.saveAgain(model, recipe: recipeIndex, into: recipe, book: book, images: images,
                                           changeSummary: "Joined with the next page, read again", in: context)
                saved.append(recipe)
            } else {
                let recipe = await ScanSaving.saveNew(model, recipe: recipeIndex, book: book, reviewed: false, images: images, appliesPointers: false, in: context)
                saved.append(recipe)
            }
        }
        let pages = PunchlistMatcher.pages(read: reading.pageNumbers)
        for (recipe, recipeIndex) in zip(saved, model.recipes.indices) {
            CrossReferenceLinking.linkWaiting(to: recipe, pages: pages, in: book, state: &state, context: context)
            CrossReferenceLinking.applySessionRule(reading.recipes[recipeIndex].crossReferences, for: recipe, in: book, state: &state, context: context)
        }
        try? context.save()
        finish(previous.id) { $0.recipes = saved.map(\.id); $0.detail = Self.savedLine(saved, skipped: false) + " · read again with the next page" }
        finish(id) { $0.detail = "Continues the page before · joined as a new version" }
        Self.logger.info("Book session: capture \(id) joined capture \(offer.previous), \(saved.count) recipes read again")
    }

    // MARK: - A contents page shot in the session (ux-notes row 114)

    /// The captures sheet's answer: Add to the Recipe List reads the page's chapters and recipes
    /// onto the list (an index page's into the book's index) and keeps it with the book as a page
    /// scan; Retake takes the capture back, for the page to be shot again.
    func resolveContents(of id: Int, add: Bool) {
        guard let index = state.captures.firstIndex(where: { $0.id == id }), state.captures[index].contentsOffer else { return }
        guard add else {
            removeCapture(id: id)
            return
        }
        state.captures[index].contentsOffer = false
        state.captures[index].detail = "Reading it as a contents page…"
        save()
        Task { await addContents(of: id) }
    }

    private func addContents(of id: Int) async {
        guard let capture = state.captures.first(where: { $0.id == id }), let reading = await readings(of: [capture]).first, !isAbandoned else { return }
        let contents = await pipeline.readContents(reading)
        let combined = reading.kind == .index ? ContentsReader.combine([], indexPages: [contents]) : ContentsReader.combine([contents])
        book.apply(combined, in: context)
        await ScanSaving.keepPageScan(ScanReviewModel(reading: reading, urls: [url(of: capture)]), kind: reading.kind == .index ? .index : .contents, book: book, images: images, in: context)
        if currentEntry == nil || currentEntry?.status != .listed { moveToNextUncaptured(after: currentEntry) }
        let added = combined.entries.count
        finish(id) { capture in
            capture.detail = !combined.index.isEmpty
                ? "An index page: \(combined.index.count) entries to the book's index"
                : "A contents page: \(combined.sections.count == 1 ? "1 chapter" : "\(combined.sections.count) chapters"), \(added == 1 ? "1 recipe" : "\(added) recipes") added to the list"
        }
        try? context.save()
    }

    // MARK: - Readings

    /// The readings of `captures`, read again from their files where this sitting never had them
    /// (an earlier sitting's last page, or one read before a relaunch).
    private func readings(of captures: [BookScanState.StoredCapture]) async -> [PageReading] {
        var found: [PageReading] = []
        for capture in captures {
            if let reading = readings[capture.id] {
                found.append(reading)
            } else if let reading = try? await Self.read(url(of: capture), quality: capture.quality?.reading, with: pipeline) {
                readings[capture.id] = reading
                found.append(reading)
            }
        }
        return found
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

    /// The recipe capture before `id` in capture order whose recipes are still in the library (a
    /// recipe deleted since leaves nothing for a page to continue).
    private func previousRecipeCapture(before id: Int) -> BookScanState.StoredCapture? {
        state.captures.filter { $0.id < id && $0.mode == .recipe && $0.status == .processed && $0.joinedTo == nil && !$0.recipes.isEmpty && !recipes(of: $0).isEmpty }.max { $0.id < $1.id }
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

    /// A page that is no recipe: reference reading (a glossary, a chapter opener, a technique)
    /// saves as a Reference with its page scan, linked to the recipes that point at it; a Sources
    /// page fills Pantry → Sources and comes off the to-scan list (ux-notes row 103); a contents or
    /// index page or other prose is kept on the book as a page scan; a blank or unreadable one is
    /// let go.
    private func keep(_ id: Int, reading: PageReading) async {
        guard let capture = state.captures.first(where: { $0.id == id }) else { return }
        let model = ScanReviewModel(reading: reading, urls: [url(of: capture)])
        switch reading.kind {
        case .prose where reading.reference != nil:
            let imported = reading.reference!
            let reference = await ReferenceSaving.save(imported, model: model, book: book, images: images, reviewed: false, in: context)
            let joined = imported.kind == .glossary && (reference.sections?.count ?? 0) > imported.sections.count
            // A look is asked for when the cook flagged it, the print read poorly, or the page
            // gave no title.
            let wantsLook = capture.flagged ?? (reading.ocrConfidence < PageStructurer.lowOCR || imported.title.isEmpty)
            finish(id) {
                $0.pageNumber = reading.pageNumber
                $0.references = [reference.id]
                $0.queued = wantsLook
                $0.detail = "Saved “\(reference.title)” as reference reading" + (joined ? " · joined the glossary" : "")
            }
        case .sources:
            let page = SourceSaving.pageNumber(of: reading, book: book, pointers: state.pointerEntries)
            await SourceSaving.keepSourcesPage(model, page: page, book: book, images: images, in: context)
            let saved = SourceSaving.save(SourcesPageReader.read(reading), book: book, in: context)
            CrossReferenceLinking.captureSourcesPage(pages: [page].compactMap(\.self), in: book, state: &state, context: context)
            finish(id) {
                $0.pageNumber = page
                $0.sources = saved.map(\.id)
                $0.detail = saved.isEmpty ? "A Sources page, kept with the book" : "A Sources page: \(saved.count == 1 ? "1 supplier" : "\(saved.count) suppliers") to Pantry"
            }
        case .contents, .index, .prose:
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

    /// The book's session, when one is alive.
    func liveSession(for bookID: UUID) -> BookScanSession? { sessions[bookID] }

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

    /// The background task (ux-notes row 92): every book with captures waiting drained in turn.
    func drainAll(in context: ModelContext) async {
        resume(in: context)
        for id in BookScanState.booksWithPendingCaptures() {
            guard !Task.isCancelled, let session = sessions[id] else { continue }
            await session.runQueue()
        }
    }

    /// The background task's time is up.
    func stopWorkers() {
        for session in sessions.values { session.stopWorker() }
    }

    /// The book is being deleted: its session stops, and its captures and state go with it.
    func forget(bookID: UUID) {
        sessions[bookID]?.abandon()
        sessions[bookID] = nil
        try? FileManager.default.removeItem(at: BookScanState.folder(for: bookID))
    }
}
