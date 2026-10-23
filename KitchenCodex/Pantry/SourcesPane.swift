import Capture
import RecipeModel
import SwiftData
import SwiftUI

/// Pantry → Sources (03 §3.17): stores and suppliers grouped Equipment · Food · Drink the way
/// cookbooks print them, the cook's favorites first (ux-notes row 129), each with what they carry,
/// its phone and website as links (Call, Safari; row 128), the book it came from, and a star
/// labelled Favorite. Call and Website stay as leading swipe actions; tapping a row opens its
/// detail, with a notes field. Filled by hand later; now by scanning a book's Sources page (02
/// Flow C step 8).
struct SourcesPane: View {
    /// One book's suppliers only: a Sources pointer in its recipe opens them.
    var book: Book?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: [SortDescriptor(\Source.name, comparator: .localizedStandard)]) private var allSources: [Source]
    /// The detail, pushed through a binding so it works in the iPhone's typed Pantry stack.
    @State private var opened: Source?
    /// The source a swipe's Delete asks about (ux-notes row 149).
    @State private var deleting: Source?

    private var sources: [Source] {
        guard let book else { return allSources }
        return allSources.filter { $0.book == book }
    }

    /// Favorites first, then the rest by what they carry.
    private var groups: [(title: String, sources: [Source])] {
        let favorites = sources.filter(\.isFrequented)
        let rest = sources.filter { !$0.isFrequented }
        let named: [(SourceCategory, String)] = [(.equipment, "Equipment"), (.food, "Food"), (.drink, "Drink")]
        var result: [(String, [Source])] = favorites.isEmpty ? [] : [("Favorites", favorites)]
        result += named.compactMap { category, title -> (String, [Source])? in
            let found = rest.filter { $0.categories.first == category }
            return found.isEmpty ? nil : (title, found)
        }
        let other = rest.filter { $0.categories.isEmpty }
        if !other.isEmpty { result.append(("Other", other)) }
        return result
    }

    var body: some View {
        Group {
            if sources.isEmpty {
                ContentUnavailableView {
                    Label("Sources", systemImage: PantryView.Pane.sources.symbol)
                } description: {
                    Text("\(PantryView.Pane.sources.emptyDescription) Scan a cookbook's Sources page from its More menu.")
                }
            } else {
                List {
                    ForEach(groups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.sources) { source in
                                SourceRow(source: source) { opened = source }
                                    .swipeActions(edge: .trailing) {
                                        // Asks first, as Delete Cookbook does (ux-notes row 149); a
                                        // swipe all the way across asks too.
                                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = source }
                                    }
                                    .confirmationDialog("Delete “\(source.name)”?", isPresented: Binding { deleting == source } set: { if !$0 { deleting = nil } }, titleVisibility: .visible) {
                                        Button("Delete Source", role: .destructive) {
                                            modelContext.delete(source)
                                            try? modelContext.save()
                                            deleting = nil
                                        }
                                    } message: {
                                        Text(source.notes.isEmpty ? "Its details go with it." : "Its details and your notes go with it.")
                                    }
                                    .swipeActions(edge: .leading) {
                                        if let phone = source.phone, let url = Self.telephone(phone) {
                                            Button("Call", systemImage: "phone") { openURL(url) }
                                                .tint(.green)
                                        }
                                        if let url = source.url {
                                            Button("Website", systemImage: "safari") { openURL(url) }
                                                .tint(.blue)
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(book.map { "Sources from \($0.displayTitle)" } ?? "Sources")
        .navigationDestination(item: $opened) { source in
            SourceDetailView(source: source)
        }
    }

    /// "(207) 555-0143" as a `tel:` link.
    static func telephone(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    /// "example.com" for a site's link.
    static func host(_ url: URL) -> String {
        url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }
}

/// Name, what they carry, the phone and site as links, the book it came from and the address, and
/// the Favorite star; the rest of the row opens its detail.
private struct SourceRow: View {
    let source: Source
    var onOpen: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if !source.carries.isEmpty {
                            Text(source.carries)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows its details and notes.")
                // The phone and site as links in the row (ux-notes row 128).
                if source.phone != nil || source.url != nil {
                    HStack(spacing: 16) {
                        if let phone = source.phone, let url = SourcesPane.telephone(phone) {
                            Button(phone) { openURL(url) }
                                .accessibilityLabel("Call \(phone)")
                        }
                        if let url = source.url {
                            Button(SourcesPane.host(url)) { openURL(url) }
                                .accessibilityLabel("Website, \(SourcesPane.host(url))")
                        }
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .lineLimit(1)
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .onTapGesture(perform: onOpen)
                }
            }
            FavoriteStar(source: source)
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let phone = source.phone, let url = SourcesPane.telephone(phone) {
                Button("Call \(phone)", systemImage: "phone") { openURL(url) }
            }
            if let url = source.url {
                Button("Website", systemImage: "safari") { openURL(url) }
            }
            if let address = source.address {
                Button("Copy Address", systemImage: "doc.on.doc") { UIPasteboard.general.string = address }
            }
        }
    }

    /// "From Nobu West · Portland, ME".
    private var detail: String? {
        var parts: [String] = []
        if let book = source.book { parts.append("From \(book.displayTitle)") }
        if let address = source.address { parts.append(address) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The star (ux-notes row 129): filled for a favorite, labelled Favorite; the model's field keeps
/// its name.
private struct FavoriteStar: View {
    let source: Source

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            source.isFrequented.toggle()
            try? modelContext.save()
        } label: {
            Image(systemName: source.isFrequented ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(source.isFrequented ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Favorite")
        .accessibilityValue(source.isFrequented ? "On" : "Off")
        .accessibilityAddTraits(source.isFrequented ? .isSelected : [])
    }
}

/// A source's detail (ux-notes row 128): its name, what it carries, its phone, site and address,
/// the books that cite it, the Favorite star, and the cook's notes (`Source.notes`).
struct SourceDetailView: View {
    @Bindable var source: Source

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: [SortDescriptor(\Source.name, comparator: .localizedStandard)]) private var allSources: [Source]

    /// The books whose Sources pages list it: its own, and others listing a supplier of its name.
    private var books: [Book] {
        let named = allSources.filter { $0.name.localizedCaseInsensitiveCompare(source.name) == .orderedSame }
        var found: [Book] = []
        for book in named.compactMap(\.book) where !found.contains(book) { found.append(book) }
        return found
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                    if !source.carries.isEmpty {
                        Text(source.carries)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                // The list's star, one control for one state (ux-notes row 129).
                LabeledContent("Favorite") {
                    FavoriteStar(source: source)
                }
            }
            if source.phone != nil || source.url != nil || source.address != nil {
                Section {
                    if let phone = source.phone, let url = SourcesPane.telephone(phone) {
                        Button { openURL(url) } label: { LabeledContent("Phone", value: phone) }
                            .accessibilityLabel("Call \(phone)")
                    }
                    if let url = source.url {
                        Button { openURL(url) } label: { LabeledContent("Website", value: SourcesPane.host(url)) }
                    }
                    if let address = source.address {
                        LabeledContent("Address", value: address)
                            .contextMenu {
                                Button("Copy Address", systemImage: "doc.on.doc") { UIPasteboard.general.string = address }
                            }
                    }
                }
            }
            if !books.isEmpty {
                Section(books.count == 1 ? "From" : "Cited in") {
                    ForEach(books) { Text($0.displayTitle) }
                }
            }
            Section("Notes") {
                TextField("Notes", text: $source.notes, prompt: Text("What to order, who to ask for"), axis: .vertical)
                    .lineLimit(3...10)
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? modelContext.save() }
    }
}

/// Saving a Sources page's suppliers (02 Flow C step 8).
@MainActor
enum SourceSaving {
    /// The page a Sources page reading is (02 Flow C step 8): its folio, else the page the book's
    /// Sources pointers name, else its Sources entry's.
    static func pageNumber(of reading: PageReading, book: Book, pointers: [BookScanState.PointerEntry]) -> Int? {
        reading.pageNumber
            ?? pointers.first { $0.kind == PageCrossReference.Kind.sources.rawValue }?.page
            ?? book.sourcesEntry?.page
    }

    /// The page kept as the book's one Sources page scan (an earlier one gives way), at `page`
    /// when its folio didn't read.
    static func keepSourcesPage(_ model: ScanReviewModel, page: Int?, book: Book, images: ScanSaving.PageImages, in context: ModelContext) async {
        for scan in book.sourcesPages where scan.pageNumber == nil || scan.pageNumber == page { context.delete(scan) }
        await ScanSaving.keepPageScan(model, kind: .sources, book: book, images: images, fallbackPage: page, in: context)
    }

    /// Each supplier as a `Source` linked to `book`; one the book already has with the same name
    /// takes the new details instead of a second row.
    @discardableResult
    static func save(_ imported: [ImportedSource], book: Book?, in context: ModelContext) -> [Source] {
        let existing = book?.sources ?? []
        var saved: [Source] = []
        for supplier in imported {
            let source: Source
            if let match = existing.first(where: { $0.name.localizedCaseInsensitiveCompare(supplier.name) == .orderedSame }) {
                source = match
            } else {
                source = Source(name: supplier.name)
                context.insert(source)
                source.book = book
            }
            source.name = supplier.name
            source.kind = kind(of: supplier.kind)
            source.categories = supplier.categories.compactMap(SourceCategory.init(rawValue:))
            if !supplier.carries.isEmpty { source.carries = supplier.carries }
            source.phone = supplier.phone ?? source.phone
            source.url = supplier.url ?? source.url
            source.address = supplier.address ?? source.address
            saved.append(source)
        }
        try? context.save()
        return saved
    }

    static func kind(of kind: ImportedSource.Kind) -> SourceKind {
        switch kind {
        case .store: .store
        case .online: .online
        case .producer: .producer
        }
    }
}
