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

/// One book on the shelf: the cover at 2:3, the completeness bar once there are entries, then the
/// title and author.
private struct BookShelfCell: View {
    let book: Book

    var body: some View {
        let progress = book.punchlistProgress
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { BookCoverImage(book: book, pointSize: 220) }
                .clipShape(.rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 0.5)
                }
            if progress.total > 0 {
                ProgressView(value: Double(progress.captured), total: Double(progress.total))
                    .accessibilityLabel("\(progress.captured) of \(progress.total) captured")
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

/// A book's cover, decoded off the main actor at the size it is shown, with the title's initial
/// where there is none, as recipe cards show theirs (03 §6 Imagery).
struct BookCoverImage: View {
    let book: Book
    /// Longest side in points; the image is decoded at this size times the display scale.
    var pointSize: CGFloat = 200

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            } else {
                Monogram(title: book.title)
            }
        }
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

    /// Every punchlist entry, across sections.
    var entries: [BookEntry] { (sections ?? []).flatMap { $0.entries ?? [] } }

    /// How much of the punchlist is captured: entries past `listed`, and recipes from the book
    /// still waiting for a look.
    var punchlistProgress: (captured: Int, total: Int, needReview: Int) {
        let entries = entries
        return (entries.count { $0.status != .listed }, entries.count, (recipes ?? []).count(where: \.needsReview))
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
