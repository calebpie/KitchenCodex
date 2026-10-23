import Capture
import RecipeModel
import SwiftData
import SwiftUI

/// The contents or index page a list entry was read from (ux-notes row 152), shown as scan review
/// shows a recipe's page: the stored page scan, the region holding the tapped line's words
/// highlighted and framed (the other regions aren't drawn: an index page has hundreds). The book
/// keeps its contents and index captures as page scans with their regions
/// (`ScanSaving.keepPageScan`), so nothing new is stored. On iPhone it sits above the list at a
/// fixed height, where the keyboard can't cover it; on iPad beside the list.
struct ContentsPagePane: View {
    let book: Book
    /// Index pages, or the contents pages.
    var kind: ScanPageKind
    /// The words of the entry under edit: its region is found by its text.
    var highlight: String?

    @State private var pages: [ContentsPage] = []
    @State private var images: [Int: UIImage] = [:]
    @State private var shown = 0
    @State private var focusRect: CGRect?
    @State private var selected: Int?

    /// One stored page: its scan and its regions as review draws them.
    struct ContentsPage: Identifiable {
        let id: Int
        let scan: RecipeImage
        let regions: [ReviewRegion]
        var pageNumber: Int? { scan.pageNumber }
    }

    /// The pane's height above the list on iPhone.
    static let compactHeight: CGFloat = 230

    var body: some View {
        VStack(spacing: 0) {
            if pages.count > 1, pages.count <= 4 {
                Picker("Page", selection: $shown) {
                    ForEach(pages) { page in
                        Text(page.pageNumber.map { "p. \($0)" } ?? "Page \(page.id + 1)").tag(page.id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)
            } else if pages.count > 4, let page = pages.first(where: { $0.id == shown }) {
                HStack {
                    Button("Previous Page", systemImage: "chevron.backward") { shown = max(0, shown - 1) }
                        .labelStyle(.iconOnly)
                        .disabled(shown == 0)
                    Spacer()
                    Text((page.pageNumber.map { "p. \($0)" } ?? "Page \(page.id + 1)") + " · \(page.id + 1) of \(pages.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Button("Next Page", systemImage: "chevron.forward") { shown = min(pages.count - 1, shown + 1) }
                        .labelStyle(.iconOnly)
                        .disabled(shown + 1 >= pages.count)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            if pages.isEmpty {
                ContentUnavailableView(kind == .index ? "No Index Page" : "No Contents Page", systemImage: "doc.text.image",
                                       description: Text(kind == .index ? "The index pages weren't photographed." : "The contents pages weren't photographed."))
            } else {
                let image = images[shown]
                let highlighted = pages.first { $0.id == shown }?.regions.filter { $0.id == selected } ?? []
                ZoomablePage(aspectRatio: image.map { $0.size.width / max(1, $0.size.height) } ?? 3 / 4, focus: focusRect) {
                    PageRegionsView(
                        image: image,
                        regions: highlighted,
                        role: { _ in nil },
                        label: { _, _ in nil },
                        selected: Set(highlighted.map(\.id))
                    ) { _ in EmptyView() }
                }
            }
        }
        .background(.background.secondary)
        .task(id: book.id) { await load() }
        .onChange(of: highlight) { _, words in find(words) }
        .onChange(of: pages.count) { _, _ in find(highlight) }
    }

    private func load() async {
        let scans = (book.pageScans ?? []).filter { $0.pageKind == kind }.sorted { ($0.pageNumber ?? .max, $0.createdAt) < ($1.pageNumber ?? .max, $1.createdAt) }
        var loaded: [ContentsPage] = []
        for (index, scan) in scans.enumerated() {
            let stored = ScanRegions.decoded(from: scan.regions)?.regions ?? []
            let regions = stored.enumerated().map { offset, region in
                ReviewRegion(id: index * 10_000 + offset, page: index, kind: region.kind, role: nil,
                             rect: CGRect(x: region.x, y: region.y, width: region.width, height: region.height),
                             lines: region.text.components(separatedBy: "\n"), confidence: region.confidence, recipe: nil)
            }
            loaded.append(ContentsPage(id: index, scan: scan, regions: regions))
        }
        pages = loaded
        for page in loaded where images[page.id] == nil {
            if let image = await ScanImage.upright(ReviewPage(id: page.id, imageData: page.scan.imageData, quarterTurns: 0, pageNumber: page.pageNumber), maxPixelSize: 2_400) {
                images[page.id] = UIImage(cgImage: image)
            }
        }
    }

    /// The region whose words best match the entry's, on whichever page: shown and framed.
    private func find(_ words: String?) {
        guard let words, !words.isEmpty else {
            selected = nil
            focusRect = nil
            return
        }
        var best: (page: Int, region: ReviewRegion, score: Double)?
        for page in pages {
            for region in page.regions where !region.isPhoto {
                let score = Self.match(words, region.text)
                if score > (best?.score ?? 0.45) { best = (page.id, region, score) }
            }
        }
        guard let best else {
            selected = nil
            return
        }
        shown = best.page
        selected = best.region.id
        focusRect = best.region.rect
    }

    /// How well the region's text holds the entry's words: 1 when it contains them whole, else
    /// the titles' word similarity.
    static func match(_ words: String, _ text: String) -> Double {
        let needle = ContentsReader.normalized(words), hay = ContentsReader.normalized(text)
        guard !needle.isEmpty, !hay.isEmpty else { return 0 }
        if hay.contains(needle) { return 1 }
        return PunchlistMatcher.similarity(words, text)
    }
}

/// Index entries edited by hand (ux-notes row 152): each line's words and page, Add Entry, swipe
/// to delete, with the index page it was read from beside or under the list.
struct IndexEditorView: View {
    let book: Book
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @FocusState private var focused: UUID?
    @State private var highlight: String?
    @State private var width: CGFloat = 0

    private var isWide: Bool { width >= 700 }

    var body: some View {
        let entries = book.indexEntries
        let hasPages = !book.pageScans(of: .index).isEmpty
        Group {
            if isWide, hasPages {
                HStack(spacing: 0) {
                    ContentsPagePane(book: book, kind: .index, highlight: highlight)
                        .frame(maxWidth: .infinity)
                    Divider()
                    list(entries)
                        .frame(width: min(440, width * 0.42))
                }
            } else if hasPages {
                // Above the list, where the keyboard can't cover it (ux-notes rows 152, 163).
                VStack(spacing: 0) {
                    ContentsPagePane(book: book, kind: .index, highlight: highlight)
                        .frame(height: ContentsPagePane.compactHeight)
                    Divider()
                    list(entries)
                }
            } else {
                list(entries)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle("Index")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", role: .confirm) { try? modelContext.save(); onDone() }
            }
        }
        .onChange(of: focused) { _, id in
            guard let id, let entry = entries.first(where: { $0.id == id }) else { return }
            highlight = entry.title
        }
    }

    private func list(_ entries: [BookEntry]) -> some View {
        List {
            Section {
                Text(entries.count == 1 ? "1 entry" : "\(entries.count) entries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Tap a line to correct it; its place on the index page shows. Swipe to delete, or add an entry the page was missing.")
            }
            Section {
                ForEach(entries) { entry in
                    IndexEntryEditorRow(entry: entry, focused: $focused) { try? modelContext.save() }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                modelContext.delete(entry)
                                try? modelContext.save()
                            }
                        }
                }
                Button("Add Entry", systemImage: "plus") { add() }
            }
        }
    }

    private func add() {
        let index = book.indexSection ?? {
            let made = BookSection(title: BookSection.indexTitle, sortOrder: 0)
            modelContext.insert(made)
            made.book = book
            return made
        }()
        let entry = BookEntry(title: "", page: nil)
        entry.sortOrder = (index.orderedEntries.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(entry)
        entry.section = index
        try? modelContext.save()
        focused = entry.id
    }
}

private struct IndexEntryEditorRow: View {
    @Bindable var entry: BookEntry
    var focused: FocusState<UUID?>.Binding
    var onCommit: () -> Void

    @State private var page = ""

    var body: some View {
        HStack(spacing: 10) {
            TextField("Entry", text: $entry.title, axis: .vertical)
                .focused(focused, equals: entry.id)
                .submitLabel(.done)
                .onSubmit { focused.wrappedValue = nil }
                .onChange(of: entry.title) { _, title in
                    guard title.contains(where: \.isNewline) else { return }
                    entry.title = title.split(whereSeparator: \.isNewline).joined(separator: " ")
                    focused.wrappedValue = nil
                }
            TextField("Page", text: $page)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                .onChange(of: page) { _, text in
                    let digits = text.filter(\.isNumber)
                    if digits != text { page = digits }
                    entry.page = Int(digits)
                }
                .accessibilityLabel("Page")
        }
        .onChange(of: focused.wrappedValue) { old, new in
            if old == entry.id, new != entry.id { onCommit() }
        }
        .onAppear { page = entry.page.map(String.init) ?? "" }
    }
}

extension Book {
    /// The page scans the book keeps of one kind, in page order.
    func pageScans(of kind: ScanPageKind) -> [RecipeImage] {
        (pageScans ?? []).filter { $0.pageKind == kind }.sorted { ($0.pageNumber ?? .max, $0.createdAt) < ($1.pageNumber ?? .max, $1.createdAt) }
    }
}
