import Capture
import RecipeModel
import SwiftData
import SwiftUI

/// Pantry → Sources (03 §3.17): stores and suppliers grouped Equipment · Food · Drink the way
/// cookbooks print them, each with what they carry, the book it came from, Call and Website as row
/// actions, and the Frequented toggle that makes a store a shopping stop (Phase 4's list). Filled
/// by hand later; now by scanning a book's Sources page (02 Flow C step 8).
struct SourcesPane: View {
    /// One book's suppliers only: a Sources pointer in its recipe opens them.
    var book: Book?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: [SortDescriptor(\Source.name, comparator: .localizedStandard)]) private var allSources: [Source]

    private var sources: [Source] {
        guard let book else { return allSources }
        return allSources.filter { $0.book == book }
    }

    private var groups: [(title: String, sources: [Source])] {
        let named: [(SourceCategory, String)] = [(.equipment, "Equipment"), (.food, "Food"), (.drink, "Drink")]
        var result = named.compactMap { category, title -> (String, [Source])? in
            let found = sources.filter { $0.categories.first == category }
            return found.isEmpty ? nil : (title, found)
        }
        let other = sources.filter { $0.categories.isEmpty }
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
                                SourceRow(source: source)
                                    .swipeActions(edge: .trailing) {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            modelContext.delete(source)
                                            try? modelContext.save()
                                        }
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
    }

    /// "(207) 555-0143" as a `tel:` link.
    static func telephone(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }
}

/// Name, what they carry, the book it came from, and the Frequented toggle.
private struct SourceRow: View {
    let source: Source

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.headline)
                    Image(systemName: symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(kindWord)
                }
                if !source.carries.isEmpty {
                    Text(source.carries)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Toggle("Frequented", isOn: Binding { source.isFrequented } set: { source.isFrequented = $0; try? modelContext.save() })
                .labelsHidden()
                .accessibilityLabel("Frequented")
                .accessibilityHint("A store you shop at, offered as a stop on the shopping list.")
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

    private var symbol: String {
        switch source.kind {
        case .store: "storefront"
        case .online: "shippingbox"
        case .producer: "leaf"
        case .other: "mappin"
        }
    }

    private var kindWord: String {
        switch source.kind {
        case .store: "Store"
        case .online: "Online"
        case .producer: "Producer"
        case .other: "Source"
        }
    }

    /// "From Nobu West · Portland, ME · 207-555-0199".
    private var detail: String? {
        var parts: [String] = []
        if let book = source.book { parts.append("From \(book.displayTitle)") }
        if let address = source.address { parts.append(address) }
        if let phone = source.phone { parts.append(phone) }
        if let host = source.url?.host()?.replacingOccurrences(of: "www.", with: "") { parts.append(host) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
