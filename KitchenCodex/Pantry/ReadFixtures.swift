#if DEBUG
import Capture
import Observation
import OSLog
import PhotosUI
import RecipeModel
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Profile → Developer, in debug builds only: **Read Fixtures** (04 §5.1 "Device readings",
/// ux-notes row 63). Reads the fixture photos with the page pipeline as Scan Page reads on this
/// device (full size on a phone, the 4,096-pixel copy in the Simulator; deterministic, no model) and
/// writes a report to the app's Documents: a JSON file of Capture's `DeviceReadingReport` records,
/// which the Mac replays (`DeviceReplayTests`), and a Markdown summary of counts only. The photos
/// come from the Photos picker or a folder in Files (its subfolders read too, in name order, ux-notes
/// row 169); the report is shared to the Mac from here. It holds page text, so it stays on the
/// device and in `Docs/Fixtures/Private`, never the repository. **Export Page Scans** (row 169)
/// shares a book's stored page scans, contents, index, recipe, reference and Sources pages, as
/// files named by kind and page, so a phone's reading can be reproduced on the Mac.
struct DeveloperSection: View {
    @State private var run = ReadFixturesRun()
    @State private var isPickingPhotos = false
    @State private var isPickingFolder = false
    @State private var items: [PhotosPickerItem] = []
    @State private var isChoosingBook = false
    @State private var exported: [URL] = []
    @State private var exportLine: String?
    @Query(sort: \Book.title) private var books: [Book]

    var body: some View {
        Section {
            // The presenters sit on their rows: a Section's modifiers apply to every row.
            Button("Read Fixtures from Photos…", systemImage: "photo.stack") { isPickingPhotos = true }
                .disabled(run.isRunning)
                .photosPicker(isPresented: $isPickingPhotos, selection: $items, maxSelectionCount: nil, selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())
                .onChange(of: items) { _, picked in
                    guard !picked.isEmpty else { return }
                    run.start(items: picked)
                    items = []
                }
            Button("Read Fixtures from a Folder…", systemImage: "folder") { isPickingFolder = true }
                .disabled(run.isRunning)
                .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
                    if case let .success(folder) = result { run.start(folder: folder) }
                }
            if run.isRunning {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reading \(run.done + 1) of \(run.total)…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { run.stop() }
                }
            } else if let files = run.files {
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.result ?? "")
                    Text(files.json.deletingLastPathComponent().lastPathComponent + "/" + files.json.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ShareLink(items: [files.json, files.summary]) {
                    Label("Share the Report", systemImage: "square.and.arrow.up")
                }
            } else if let failure = run.failure {
                Text(failure)
                    .foregroundStyle(.secondary)
            }
            Button("Export Page Scans…", systemImage: "doc.on.doc") { isChoosingBook = true }
                .disabled(books.isEmpty)
                .confirmationDialog("Which book's page scans?", isPresented: $isChoosingBook, titleVisibility: .visible) {
                    ForEach(books.filter { !($0.pageScans ?? []).isEmpty }) { book in
                        Button("\(book.displayTitle) (\((book.pageScans ?? []).count))") { export(book) }
                    }
                }
            if !exported.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exportLine ?? "")
                    Text(exported[0].deletingLastPathComponent().lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ShareLink(items: exported) {
                    Label("Share the Page Scans", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Read Fixtures reads the photos you pick, or every photo in a folder and its subfolders, with the page pipeline as Scan Page reads them on this device, and writes the reader's blocks and the structured result for each to a report in the app's Documents. Export Page Scans writes a book's stored page scans to Documents as files named by kind and page.")
        }
    }

    /// Documents/Page Scans/<book>/<kind>-p<page>-<n>.jpg for every page scan the book keeps.
    private func export(_ book: Book) {
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let slug = book.displayTitle.lowercased().replacing(/[^a-z0-9]+/, with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let folder = documents.appending(path: "Page Scans/\(slug.isEmpty ? book.id.uuidString : slug)", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var written: [URL] = []
            var counts: [String: Int] = [:]
            let scans = (book.pageScans ?? []).sorted { ($0.pageKind?.rawValue ?? "", $0.pageNumber ?? .max, $0.createdAt) < ($1.pageKind?.rawValue ?? "", $1.pageNumber ?? .max, $1.createdAt) }
            for scan in scans {
                let kind = scan.pageKind?.rawValue ?? "page"
                counts[kind, default: 0] += 1
                let name = "\(kind)-p\(scan.pageNumber.map(String.init) ?? "none")-\(counts[kind]!).jpg"
                let url = folder.appending(path: name)
                guard let data = scan.imageData else { continue }
                try data.write(to: url)
                written.append(url)
            }
            exported = written
            exportLine = "\(written.count) page scans written: " + counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
        } catch {
            exported = []
            exportLine = "The page scans couldn't be written: \(error.localizedDescription)"
        }
    }
}

/// One Read Fixtures run: the photos read one at a time off the main actor, the report written
/// when the last is done (or when stopped, with what was read).
@MainActor
@Observable
final class ReadFixturesRun {
    static let albumName = "Kitchen Codex Fixtures"

    private(set) var isRunning = false
    private(set) var done = 0
    private(set) var total = 0
    private(set) var result: String?
    private(set) var failure: String?
    private(set) var files: (json: URL, summary: URL)?
    private var work: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.calebpietrafesa.KitchenCodex", category: "scan")

    /// A photo to read: where to load it from, its name and its Photos identifier.
    private enum Source {
        case item(PhotosPickerItem)
        case file(URL)
    }

    func start(items: [PhotosPickerItem]) {
        begin(items.map(Source.item), scope: nil)
    }

    /// A folder's photos, and its subfolders' after them, each folder in name order (ux-notes row
    /// 169: the nine book folders in one run).
    func start(folder: URL) {
        let scoped = folder.startAccessingSecurityScopedResource()
        func photos(in folder: URL) -> [URL] {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentTypeKey, .isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            let sorted = items.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            let own = sorted.filter { (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true }
            let folders = sorted.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && $0.lastPathComponent != "Raw" }
            return own + folders.flatMap { photos(in: $0) }
        }
        let photos = photos(in: folder)
        guard !photos.isEmpty else {
            if scoped { folder.stopAccessingSecurityScopedResource() }
            failure = "That folder has no photos."
            return
        }
        begin(photos.map(Source.file), scope: scoped ? folder : nil)
    }

    func stop() {
        work?.cancel()
    }

    private func begin(_ sources: [Source], scope: URL?) {
        isRunning = true
        done = 0
        total = sources.count
        result = nil
        failure = nil
        files = nil
        var pipeline = ScanSession.makePipeline()
        pipeline.model = nil
        let report = DeviceReadingReport(device: Self.deviceName, build: BuildInfo.current.map { "\($0.commit) · \($0.date?.formatted(.iso8601) ?? "")" }, readerMaxPixelSize: pipeline.reader.maxPixelSize)
        work = Task {
            var report = report
            let folder = FileManager.default.temporaryDirectory.appending(path: "fixtures-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for source in sources {
                guard !Task.isCancelled else { break }
                let photo = await Self.read(source, into: folder, with: pipeline)
                report.photos.append(photo)
                done += 1
            }
            try? FileManager.default.removeItem(at: folder)
            scope?.stopAccessingSecurityScopedResource()
            write(report)
            isRunning = false
        }
    }

    /// One photo: copied out of Photos or Files, read as Scan Page reads it, the copy deleted.
    private static func read(_ source: Source, into folder: URL, with pipeline: PagePipeline) async -> DeviceReadingReport.Photo {
        let name: String
        let assetID: String?
        let url: URL?
        switch source {
        case let .item(item):
            let picked = try? await item.loadTransferable(type: PickedPhoto.self)
            assetID = item.itemIdentifier
            name = picked?.url.lastPathComponent ?? item.itemIdentifier ?? "photo"
            url = picked.map { picked in
                let copy = folder.appending(path: "\(UUID().uuidString)-\(picked.url.lastPathComponent)")
                try? FileManager.default.moveItem(at: picked.url, to: copy)
                return copy
            }
        case let .file(file):
            assetID = nil
            name = file.lastPathComponent
            let copy = folder.appending(path: "\(UUID().uuidString)-\(file.lastPathComponent)")
            url = (try? FileManager.default.copyItem(at: file, to: copy)) != nil ? copy : nil
        }
        guard let url else { return DeviceReadingReport.Photo(fileName: name, assetID: assetID, error: "The photo couldn't be opened.") }
        defer { try? FileManager.default.removeItem(at: url) }
        return await readPhoto(at: url, name: name, assetID: assetID, with: pipeline)
    }

    @concurrent
    nonisolated private static func readPhoto(at url: URL, name: String, assetID: String?, with pipeline: PagePipeline) async -> DeviceReadingReport.Photo {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let read = try await pipeline.readForReport(contentsOf: url)
            let seconds = (clock.now - start) / .seconds(1)
            return DeviceReadingReport.Photo(fileName: name, assetID: assetID, read: read, seconds: seconds)
        } catch {
            return DeviceReadingReport.Photo(fileName: name, assetID: assetID, seconds: (clock.now - start) / .seconds(1), error: String(describing: error))
        }
    }

    /// Documents/Read Fixtures/Read Fixtures <date>.json and .md.
    private func write(_ report: DeviceReadingReport) {
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = documents.appending(path: "Read Fixtures", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = report.createdAt.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)", timeZone: .current, calendar: .current))
            let json = folder.appending(path: "Read Fixtures \(stamp).json")
            let summary = folder.appending(path: "Read Fixtures \(stamp).md")
            try report.encoded().write(to: json)
            try Data(report.summaryMarkdown.utf8).write(to: summary)
            files = (json, summary)
            let recipes = report.photos.compactMap(\.result).reduce(0) { $0 + $1.recipes.count }
            result = "\(report.photos.count) photos read, \(recipes) recipes; report saved."
            Self.logger.info("Read Fixtures: \(report.photos.count) photos, \(recipes) recipes, report at \(json.path, privacy: .public)")
        } catch {
            failure = "The report couldn't be written: \(error.localizedDescription)"
        }
    }

    /// "iPhone18,1 · iOS 27.0".
    private static var deviceName: String {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"].map { "\($0) Simulator" } ?? machine
        return "\(model) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }
}

/// A photo from the Photos picker as a file, so its name (IMG_1051.HEIC) comes with it.
private struct PickedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let folder = FileManager.default.temporaryDirectory.appending(path: "picked-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedPhoto(url: copy)
        }
    }
}
#endif
