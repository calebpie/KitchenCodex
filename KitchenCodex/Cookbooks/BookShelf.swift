import Foundation
import RecipeModel
import SwiftData
import SwiftUI
import UIKit

/// The Cookbooks view's shelf (03 §3.7): a grid of covers, each with its title and author under it
/// and, once the book has a punchlist, a thin completeness bar under the cover. A tap pushes Book
/// detail over the shelf, as a recipe pushes over the grid. `header` is the scrolling content's
/// first item: the title switch on iPhone.
struct BookShelf<Header: View>: View {
    /// In the shelf's order (More → Sort By).
    let books: [Book]
    let isWide: Bool
    @ViewBuilder let header: Header

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                // 100 pt gives three covers across an iPhone; 150 about six beside the iPad sidebar.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: isWide ? 150 : 100), spacing: 16, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(books) { book in
                        NavigationLink(value: LibraryRoute.book(book.persistentModelID)) {
                            BookShelfCell(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
    }
}

/// One book on the shelf: the cover whole at the shelf's cover height with its own width, standing
/// on the base line (ux-notes row 150), the completeness bar once the book's progress can be
/// told (row 165), then the title and author.
private struct BookShelfCell: View {
    let book: Book

    /// The cover height shared by every cell, so narrow and wide books sit on one shelf.
    static let coverHeight: CGFloat = 150

    var body: some View {
        let progress = book.punchlistProgress
        VStack(alignment: .leading, spacing: 8) {
            BookCoverImage(book: book, pointSize: 220)
                .frame(height: Self.coverHeight)
                .frame(maxWidth: .infinity, alignment: .bottomLeading)
            if let progress {
                ProgressView(value: Double(progress.captured), total: Double(progress.total))
                    .accessibilityLabel(progress.line)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .hoverEffect(.lift)
    }
}

/// A book's cover, decoded off the main actor at the size it is shown, shown whole at the height
/// its parent gives it with its own width, its corners and hairline drawn on its own bounds
/// (ux-notes row 150); the title's initial on a 2:3 card where there is none, as recipe cards show
/// theirs (03 §6 Imagery).
struct BookCoverImage: View {
    let book: Book
    /// Longest side in points; the image is decoded at this size times the display scale.
    var pointSize: CGFloat = 200

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
            } else {
                Monogram(title: book.title)
                    .aspectRatio(2 / 3, contentMode: .fit)
            }
        }
        .clipShape(.rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5) }
        .task(id: cacheKey) {
            image = await load()
        }
    }

    private var maxPixelSize: CGFloat { pointSize * displayScale }

    /// The cover's size stands in for an edit time, which `Book` doesn't keep: a new cover from
    /// Edit Book Info decodes afresh.
    private var cacheKey: String {
        "book-\(book.id.uuidString)-\(book.coverImageData?.count ?? 0)-\(Int(maxPixelSize))"
    }

    private func load() async -> UIImage? {
        if let cached = ThumbnailCache.shared.object(forKey: cacheKey as NSString) { return cached }
        guard let data = book.coverImageData, let decoded = await ImageProcessing.thumbnail(from: data, maxPixelSize: maxPixelSize) else { return nil }
        ThumbnailCache.shared.setObject(decoded, forKey: cacheKey as NSString)
        return decoded
    }
}

/// Cookbooks → More → Sort By.
enum BookSort: String, CaseIterable, Identifiable {
    case title, author

    var id: Self { self }

    var title: String {
        switch self {
        case .title: "Title"
        case .author: "Author"
        }
    }

    /// `books` (already in title order) in this order. Author sorts by the first author's family
    /// name, then by title; books without an author come last.
    func sorted(_ books: [Book]) -> [Book] {
        switch self {
        case .title:
            return books
        case .author:
            return books.sorted { first, second in
                let a = first.authorSortKey, b = second.authorSortKey
                if a.isEmpty != b.isEmpty { return b.isEmpty }
                let order = a.localizedStandardCompare(b)
                return order == .orderedSame
                    ? first.displayTitle.localizedStandardCompare(second.displayTitle) == .orderedAscending
                    : order == .orderedAscending
            }
        }
    }
}

extension Book {
    /// The title, or "Untitled Cookbook" for a book saved without one.
    var displayTitle: String { title.isEmpty ? "Untitled Cookbook" : title }

    /// Every punchlist entry, across its chapters (the index's entries are not the punchlist's).
    var entries: [BookEntry] { (sections ?? []).filter { !$0.isIndex }.flatMap { $0.entries ?? [] } }

    /// How far the book is captured (ux-notes row 165), or nil while no contents or index page
    /// has been captured, when nothing can say how much of the book there is. Where the list has
    /// recipes, the entries the contents or the cook listed plus the recipes captured, a recipe the
    /// list lacked counting in both, entries page pointers made left out; where the contents gave
    /// chapters with pages but no recipes (Bouchon), the pages captured so far against the largest
    /// page number the contents list, and `isByPages` says so. `needReview` counts the book's
    /// recipes and references waiting for a look.
    var punchlistProgress: PunchlistProgress? {
        let needReview = (recipes ?? []).count(where: \.needsReview) + ReferenceSaving.reviewQueue(for: self).count
        guard hasContentsPages else { return nil }
        let pointerEntries = Set(BookScanStore.shared.state(for: self)?.pointerEntries.filter(\.madeEntry).map(\.entry) ?? [])
        let listed = entries.filter { !pointerEntries.contains($0.id) }
        if !listed.isEmpty {
            return PunchlistProgress(captured: listed.count { $0.status != .listed }, total: listed.count, needReview: needReview, isByPages: false)
        }
        // Chapters alone: progress by the pages captured against the contents' last page.
        let last = orderedSections.compactMap(\.startPage).max() ?? 0
        guard last > 0 else { return nil }
        let captured = Set((recipes ?? []).compactMap(\.pageNumber)).count
        return PunchlistProgress(captured: min(captured, last), total: last, needReview: needReview, isByPages: true)
    }

    /// The recipes and references of the book waiting for a look, whatever its list.
    var reviewCount: Int {
        (recipes ?? []).count(where: \.needsReview) + ReferenceSaving.reviewQueue(for: self).count
    }

    /// A contents or index page has been captured (kept as a page scan), or the list was built
    /// from one: the book's extent is known.
    var hasContentsPages: Bool {
        (pageScans ?? []).contains { $0.pageKind == .contents || $0.pageKind == .index } || !orderedSections.isEmpty && !entries.isEmpty && orderedSections.contains { $0.startPage != nil }
    }

    /// The first author's family name and given names ("López-Alt J. Kenji"), so the shelf sorts by
    /// surname. `author` holds the names as one list ("Pat Example and Sam Sample").
    var authorSortKey: String {
        let first = author.components(separatedBy: " and ").first?.components(separatedBy: ", ").first ?? author
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        guard let components = PersonNameComponentsFormatter().personNameComponents(from: trimmed),
              let family = components.familyName, !family.isEmpty else { return trimmed }
        return [family, components.givenName, components.middleName].compactMap(\.self).joined(separator: " ")
    }
}

/// How far a book is captured, for the shelf's bar and the detail's ring (ux-notes row 165).
struct PunchlistProgress: Equatable {
    var captured: Int
    var total: Int
    var needReview: Int
    /// Inferred from the pages captured against the contents' last page, the list having chapters
    /// but no recipes.
    var isByPages: Bool

    /// "47 of 112 captured", "about 12 of 320 pages captured", with ", 3 need review".
    var line: String {
        let base = isByPages ? "about \(captured) of \(total) pages captured" : "\(captured) of \(total) captured"
        return needReview > 0 ? "\(base), \(needReview == 1 ? "1 needs review" : "\(needReview) need review")" : base
    }
}
