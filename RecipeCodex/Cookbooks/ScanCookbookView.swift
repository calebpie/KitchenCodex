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
/// Build the Recipe List from the contents pages, corrected inline, then the whole-book session.
/// Done for Now after the card leaves the book on the shelf, with Continue Scanning in its detail.
/// A book already on the shelf whose barcode is scanned again goes straight to its session, or to
/// Build the Recipe List while it has no list.
struct ScanCookbookView: View {
    /// The book to show once the sheet has gone.
    var onFinish: (Book?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.barcode
    @State private var scanning: Book?

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
                    CookbookStartView(book: book) { step = .contents(book) } onDone: { finish(book) }
                }
            case let .contents(book):
                NavigationStack {
                    BuildRecipeListView(book: book) { step = .list(book) }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done for Now") { finish(book) }
                            }
                        }
                }
            case let .list(book):
                NavigationStack {
                    PunchlistEditorView(book: book) { scanning = book } onDone: { finish(book) }
                }
            }
        }
        .fullScreenCover(item: $scanning, onDismiss: { if let book = currentBook { finish(book) } }) { book in
            BookScanView(book: book)
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
        guard !book.orderedEntries.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            scanning = book
        }
    }

    private func finish(_ book: Book) {
        onFinish(book)
        dismiss()
    }
}

/// After the card: Build the Recipe List from the contents pages, or Done for Now.
private struct CookbookStartView: View {
    let book: Book
    var onBuild: () -> Void
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
/// listed entries, and kept with the book as page scans.
struct BuildRecipeListView: View {
    let book: Book
    /// The list is on the book: on to the inline correction.
    var onRead: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var phase = Phase.choosing
    @State private var pages: [PageLine] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isChoosingPhotos = false
    @State private var isChoosingFiles = false
    @State private var isShowingCamera = false
    @State private var camera = ContentsCaptureSink()

    enum Phase: Equatable {
        case choosing, reading, nothingFound
    }

    /// One contents page's progress: counts only.
    struct PageLine: Identifiable, Equatable {
        let id: Int
        var line = "Waiting…"
        var isDone = false
    }

    private static let logger = Logger(subsystem: "com.calebpietrafesa.RecipeCodex", category: "books")

    var body: some View {
        List {
            switch phase {
            case .choosing:
                Section {
                    if CameraAccess.isAvailable {
                        Button("Photograph the Contents Pages", systemImage: "camera") {
                            Task { if await CameraAccess.request() { isShowingCamera = true } }
                        }
                        .disabled(CameraAccess.isDenied)
                    }
                    Button("From Photo", systemImage: "photo.on.rectangle") { isChoosingPhotos = true }
                    Button("Files", systemImage: "folder") { isChoosingFiles = true }
                } footer: {
                    Text("Every contents page, in order, and the index too if you like: contents pages come first. The recipes and their pages are read off them, and you can correct the list before you start.")
                }
            case .reading, .nothingFound:
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
            PageCameraView(session: camera) {
                isShowingCamera = false
                Task { await read(urls: camera.urls) }
            } onClose: {
                isShowingCamera = false
                camera.discard()
            }
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
            if reading.kind == .index { index.append(read) } else { contents.append(read) }
            let count = read.entries.count
            pages[number].line = count == 0
                ? (read.sections.isEmpty ? "No recipes found" : "\(read.sections.count) chapters")
                : "\(read.sections.count) chapters, \(count) recipes" + (read.method == .model ? " (Apple Intelligence)" : "")
            pages[number].isDone = true
            // The contents page stays with the book, as a page scan.
            await ScanSaving.keepPageScan(ScanReviewModel(reading: reading, urls: [url]), kind: reading.kind == .index ? .index : .contents, book: book, images: images, in: modelContext)
        }
        let combined = ContentsReader.combine(contents, indexPages: index)
        Self.logger.info("Build the Recipe List: \(urls.count) pages, \(combined.sections.count) sections, \(combined.entries.count) entries, \(combined.pagedEntryCount) with a page")
        guard !combined.sections.isEmpty else {
            phase = .nothingFound
            return
        }
        book.apply(combined, in: modelContext)
        onRead()
    }

    @concurrent
    nonisolated private static func read(_ url: URL, with pipeline: PagePipeline) async throws -> (PageReading, BookContents) {
        let reading = try await pipeline.readPage(contentsOf: url, page: 0, of: 1)
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
    var urls: [URL] { captures.filter { $0.mode == .recipe }.map(\.url) }
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
}
