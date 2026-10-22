import Capture
import Observation
import OSLog
import PhotosUI
import RecipeModel
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Add → Scan Cookbook (02 Flow C, 03 §3.7–3.8, 04 §5.1 "Add Cookbook"): the barcode first (the
/// live scanner on a device, a photo or file of it in the Simulator) and Add Cookbook's card, then
/// Build the Recipe List from the contents pages, corrected inline, then the whole-book session;
/// or Scan Recipes Instead, the session with no list, which grows as pages are scanned (ux-notes
/// row 114). Done for Now after the card leaves the book on the shelf, with Continue Scanning in
/// its detail. A book already on the shelf whose barcode is scanned again goes straight to its
/// session, or to Build the Recipe List while it has no list.
struct ScanCookbookView: View {
    /// The book to show once the sheet has gone.
    var onFinish: (Book?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.barcode
    /// The session, with any recipe pages offered as contents pages, which it takes as its first
    /// captures (carried in the item, so the cover gets them as they are when it opens).
    @State private var scanning: Scanning?

    struct Scanning: Identifiable {
        let id = UUID()
        let book: Book
        var pages: [URL] = []
    }

    enum Step {
        case barcode
        case start(Book)
        case contents(Book)
        case list(Book)
    }

    var body: some View {
        Group {
            switch step {
            case .barcode:
                AddCookbookView(title: "Scan Cookbook", continuesToScanning: true) { book in arrive(book) }
            case let .start(book):
                NavigationStack {
                    CookbookStartView(book: book) { step = .contents(book) } onScanInstead: { scanning = Scanning(book: book) } onDone: { finish(book) }
                }
            case let .contents(book):
                NavigationStack {
                    BuildRecipeListView(book: book) { step = .list(book) } onScanRecipes: { pages in
                        scanning = Scanning(book: book, pages: pages)
                    }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done for Now") { finish(book) }
                            }
                        }
                }
            case let .list(book):
                NavigationStack {
                    PunchlistEditorView(book: book) { scanning = Scanning(book: book) } onDone: { finish(book) }
                }
            }
        }
        .fullScreenCover(item: $scanning, onDismiss: { if let book = currentBook { finish(book) } }) { start in
            BookScanView(book: start.book, firstPages: start.pages)
        }
    }

    private var currentBook: Book? {
        switch step {
        case .barcode: nil
        case let .start(book), let .contents(book), let .list(book): book
        }
    }

    /// The card's book: its session when it has a list, else the start. The session is presented
    /// once the sheet has settled on the new step: presented while the barcode step is torn down,
    /// the cover came up under the status bar and wouldn't close.
    private func arrive(_ book: Book) {
        step = .start(book)
        guard !book.orderedSections.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            scanning = Scanning(book: book)
        }
    }

    private func finish(_ book: Book) {
        onFinish(book)
        dismiss()
    }
}

/// After the card: Build the Recipe List from the contents pages, Scan Recipes Instead, or Done
/// for Now.
private struct CookbookStartView: View {
    let book: Book
    var onBuild: () -> Void
    var onScanInstead: () -> Void
    var onDone: () -> Void

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Color.clear
                        .frame(width: 60, height: 90)
                        .overlay { BookCoverImage(book: book, pointSize: 100) }
                        .clipShape(.rect(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.displayTitle).font(.headline)
                        if !book.author.isEmpty {
                            Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("On your shelf").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section {
                Button(action: onBuild) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Build the Recipe List").foregroundStyle(.primary)
                            Text("Photograph or choose the contents pages; the recipes and their pages become the list you scan from.")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                        }
                    } icon: {
                        Image(systemName: "list.number")
                    }
                    .padding(.vertical, 4)
                }
                Button(action: onScanInstead) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan Recipes Instead").foregroundStyle(.primary)
                            Text("No list to start: the list grows as you scan recipe pages.")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                        }
                    } icon: {
                        Image(systemName: "camera.viewfinder")
                    }
                    .padding(.vertical, 4)
                }
                Button(action: onDone) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Done for Now").foregroundStyle(.primary)
                            Text("The book stays on your shelf; Continue Scanning in its detail picks up here.")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                        }
                    } icon: {
                        Image(systemName: "books.vertical")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Scan Cookbook")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Build the Recipe List (02 Flow C step 3): the contents pages photographed (on a device) or
/// chosen from Photos or Files, read into chapters and `[title, page]` entries (`ContentsReader`,
/// the on-device model only for a page that reads few entries), added to the book's punchlist as
/// listed entries, and kept with the book as page scans; index pages fill the book's index. A page
/// that reads as a recipe page is set aside and named, with Scan It as a Recipe (the book session,
/// the page its first capture) and Retake (ux-notes row 114).
struct BuildRecipeListView: View {
    let book: Book
    /// The list is on the book: on to the inline correction.
    var onRead: () -> Void
    /// Scan It as a Recipe: the pages set aside as recipe pages, for the book session.
    var onScanRecipes: ([URL]) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var phase = Phase.choosing
    @State private var pages: [PageLine] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isChoosingPhotos = false
    @State private var isChoosingFiles = false
    @State private var isShowingCamera = false
    @State private var camera = ContentsCaptureSink()
    /// Pages that read as recipe pages, not contents pages.
    @State private var recipePages: [URL] = []
    /// Where the last pages came from, for Retake.
    @State private var source = Source.photos
    /// Whether the pages read gave the book a list.
    @State private var foundList = false

    enum Phase: Equatable {
        case choosing, reading, nothingFound, recipePages
    }

    enum Source {
        case camera, photos, files
    }

    /// One contents page's progress: counts only.
    struct PageLine: Identifiable, Equatable {
        let id: Int
        var line = "Waiting…"
        var isDone = false
    }

    private static let logger = Logger(subsystem: "com.calebpietrafesa.KitchenCodex", category: "books")

    var body: some View {
        List {
            switch phase {
            case .choosing:
                Section {
                    if CameraAccess.isAvailable {
                        Button("Photograph the Contents Pages", systemImage: "camera") {
                            source = .camera
                            Task { if await CameraAccess.request() { isShowingCamera = true } }
                        }
                        .disabled(CameraAccess.isDenied)
                    }
                    Button("From Photo", systemImage: "photo.on.rectangle") { source = .photos; isChoosingPhotos = true }
                    Button("Files", systemImage: "folder") { source = .files; isChoosingFiles = true }
                } footer: {
                    Text("Every contents page, in order, and the index too if you like: contents pages come first. The recipes and their pages are read off them, and you can correct the list before you start.")
                }
            case .reading, .nothingFound, .recipePages:
                Section("Contents Pages") {
                    ForEach(pages) { page in
                        HStack {
                            Text("Page \(page.id + 1)")
                            Spacer()
                            if page.isDone {
                                Text(page.line).foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                            }
                        }
                    }
                }
                if phase == .recipePages {
                    Section {
                        Text(recipePages.count == 1 ? "This looks like a recipe page, not a contents page." : "These look like recipe pages, not contents pages.")
                        Button(recipePages.count == 1 ? "Scan It as a Recipe" : "Scan Them as Recipes") { onScanRecipes(recipePages) }
                        Button(source == .camera ? "Retake" : "Choose Again", action: retake)
                        if foundList {
                            Button("Continue to the List", action: onRead)
                        }
                    }
                }
                if phase == .nothingFound {
                    Section {
                        Text("No recipe titles with page numbers were found on those pages.")
                            .foregroundStyle(.secondary)
                        Button("Choose Other Pages") { phase = .choosing }
                        Button("Enter the List by Hand", action: onRead)
                    }
                }
            }
        }
        .navigationTitle("Build the Recipe List")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $isChoosingPhotos, selection: $photoItems, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())
        .fileImporter(isPresented: $isChoosingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            let files = urls.compactMap { url -> (Data, String)? in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return (try? Data(contentsOf: url)).map { ($0, url.pathExtension.isEmpty ? "jpg" : url.pathExtension) }
            }
            Task { await read(files) }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task {
                var files: [(Data, String)] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        files.append((data, item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"))
                    }
                }
                await read(files)
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            // Every capture here is a page: no Recipe · Photo switch (ux-notes row 116).
            PageCameraView(session: camera, showsCaptureMode: false) {
                isShowingCamera = false
                let urls = camera.urls
                camera.handOver()
                Task { await read(urls: urls) }
            } onClose: {
                isShowingCamera = false
                camera.discard()
            }
        }
    }

    /// Retake: the camera again, or Photos or Files.
    private func retake() {
        recipePages = []
        phase = .choosing
        switch source {
        case .camera: isShowingCamera = true
        case .photos: isChoosingPhotos = true
        case .files: isChoosingFiles = true
        }
    }

    private func read(_ files: [(Data, String)]) async {
        let folder = FileManager.default.temporaryDirectory.appending(path: "contents-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = files.enumerated().compactMap { index, file -> URL? in
            let url = folder.appending(path: "contents-\(index + 1).\(file.1)")
            return (try? file.0.write(to: url)) != nil ? url : nil
        }
        await read(urls: urls)
    }

    private func read(urls: [URL]) async {
        guard !urls.isEmpty else { return }
        phase = .reading
        recipePages = []
        foundList = false
        pages = urls.indices.map { PageLine(id: $0) }
        let pipeline = ScanSession.makePipeline()
        var contents: [BookContents] = []
        var index: [BookContents] = []
        let images = ScanSaving.PageImages()
        for (number, url) in urls.enumerated() {
            guard let (reading, read) = try? await Self.read(url, with: pipeline) else {
                pages[number].line = "Couldn't be read"
                pages[number].isDone = true
                continue
            }
            guard let read else {
                // A recipe page, not a contents page (ux-notes row 114): set aside, not read as one.
                recipePages.append(url)
                pages[number].line = "A recipe page"
                pages[number].isDone = true
                continue
            }
            if reading.kind == .index { index.append(read) } else { contents.append(read) }
            let count = read.entries.count
            pages[number].line = !read.index.isEmpty
                ? "Index, \(read.index.count) entries"
                : count == 0
                ? (read.sections.isEmpty ? "No recipes found" : Self.chapters(read.sections.count))
                : "\(Self.chapters(read.sections.count)), \(count == 1 ? "1 recipe" : "\(count) recipes")" + (read.method == .model ? " (Apple Intelligence)" : "")
            pages[number].isDone = true
            // The contents page stays with the book, as a page scan.
            await ScanSaving.keepPageScan(ScanReviewModel(reading: reading, urls: [url]), kind: reading.kind == .index ? .index : .contents, book: book, images: images, in: modelContext)
        }
        let combined = ContentsReader.combine(contents, indexPages: index)
        Self.logger.info("Build the Recipe List: \(urls.count) pages, \(combined.sections.count) sections, \(combined.entries.count) entries, \(combined.pagedEntryCount) with a page, \(combined.index.count) index entries, \(recipePages.count) recipe pages")
        if !combined.sections.isEmpty || !combined.index.isEmpty {
            book.apply(combined, in: modelContext)
            foundList = !combined.sections.isEmpty
        }
        if !recipePages.isEmpty {
            phase = .recipePages
        } else if combined.sections.isEmpty {
            phase = .nothingFound
        } else {
            onRead()
        }
    }

    /// "1 chapter", "14 chapters".
    private static func chapters(_ count: Int) -> String {
        count == 1 ? "1 chapter" : "\(count) chapters"
    }

    /// A page's reading and its contents; nil contents for a page that reads as a recipe page.
    @concurrent
    nonisolated private static func read(_ url: URL, with pipeline: PagePipeline) async throws -> (PageReading, BookContents?) {
        let reading = try await pipeline.readContentsPage(contentsOf: url)
        if ContentsReader.judge(reading) == .recipe { return (reading, nil) }
        return (reading, await pipeline.readContents(reading))
    }
}

/// The camera's sink while photographing contents pages: the pages kept in order, read once the
/// cook taps Done.
@MainActor
@Observable
final class ContentsCaptureSink: PageCaptureSink {
    private(set) var captures: [CaptureItem] = []
    var scannedISBN: String?
    var asksToCleanLens = false
    var namesBookByBarcode: Bool { false }
    var lastCapturePreview: [CapturePreviewBlock] { [] }
    var isReadingCaptures: Bool { false }
    var captureItems: [CaptureItem] { captures }
    /// Every capture: each is a page here (ux-notes row 116).
    var urls: [URL] { captures.map(\.url) }
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private lazy var folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appending(path: "contents-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    func captureFolder() -> URL { folder }

    func reserveCaptureID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    func addCapture(id: Int, at url: URL, mode: CaptureMode, quality: PageQualityReading?, note: String) {
        captures.append(CaptureItem(id: id, url: url, mode: mode, note: note))
    }

    func removeCapture(id: Int) {
        if let capture = captures.first(where: { $0.id == id }) { try? FileManager.default.removeItem(at: capture.url) }
        captures.removeAll { $0.id == id }
    }

    func setMode(_ mode: CaptureMode, ofCapture id: Int) {
        if let index = captures.firstIndex(where: { $0.id == id }) { captures[index].mode = mode }
    }

    func shelfBook(isbn: String) -> Book? { nil }

    func discard() {
        for capture in captures { try? FileManager.default.removeItem(at: capture.url) }
        captures = []
    }

    /// The pages are read now: the next sitting starts with none, the files left for the reading.
    func handOver() {
        captures = []
    }
}
