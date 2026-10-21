import Capture
import Foundation
import RecipeModel
import SwiftData
import SwiftUI

// Page pointers resolved at display time (04 §5.1 "Page pointers", ux-notes row 74): what a book
// holds from a page, by book and page number, with no schema field. A recipe scanned from the
// page, a Reference captured from it (its entry opened when the pointer names one), or nothing
// yet, which offers Scan Page N at the pill (ux-notes row 104).

/// What a book holds from one page.
enum PageHolding {
    case recipe(Recipe)
    case reference(Reference)
    /// Nothing captured: the listed entry at that page, when the list has one.
    case nothing(page: Int, entry: BookEntry?)
}

extension Book {
    /// Recipes scanned from `page`: printed on it, or running over it.
    func recipes(onPage page: Int) -> [Recipe] {
        var found = (recipes ?? []).filter { recipe in
            if recipe.pageNumber == page { return true }
            guard let first = recipe.source?.firstPage, let last = recipe.source?.lastPage else { return false }
            return first <= page && page <= last
        }
        // A recipe on that page's entry whose own page was misread still counts.
        for entry in orderedEntries where entry.page == page {
            if let recipe = entry.recipe, !found.contains(recipe) { found.append(recipe) }
        }
        return found
    }

    /// References captured from `page`: their entry's page, or the pages their source spans.
    func references(onPage page: Int) -> [Reference] {
        (references ?? []).filter { reference in
            if reference.bookEntry?.page == page { return true }
            guard let first = reference.source?.firstPage else { return false }
            return first <= page && page <= (reference.source?.lastPage ?? first)
        }
    }

    /// What the book holds from `pages` (the first that holds anything), for a pointer in
    /// `pointing`: a recipe other than the one pointing, the one `target` names first; else a
    /// Reference; else nothing, with the first page's listed entry.
    func holding(pages: [Int], named target: String?, from pointing: Recipe?) -> PageHolding {
        for page in pages {
            let recipes = recipes(onPage: page).filter { $0 != pointing }
            if let target, let named = recipes.max(by: { PunchlistMatcher.similarity($0.title, target) < PunchlistMatcher.similarity($1.title, target) }),
               PunchlistMatcher.similarity(named.title, target) > 0 {
                return .recipe(named)
            }
            if let first = recipes.min(by: { $0.createdAt < $1.createdAt }) { return .recipe(first) }
            if let reference = references(onPage: page).first { return .reference(reference) }
        }
        let page = pages.first ?? 0
        return .nothing(page: page, entry: orderedEntries.first { $0.page == page && $0.recipe == nil && $0.reference == nil })
    }
}

/// Scan Page N, offered where the book holds nothing from a pointer's page: what the pill shows,
/// anchored at the pill (a step's) or the row (an ingredient line's), as the As Written popover is
/// (ux-notes row 104).
struct ScanOffer: Identifiable, Equatable {
    let id = UUID()
    let page: Int
    /// The entry the scan adds or finds.
    let title: String
    let pointer: PagePointer
    let bookTitle: String
}

/// "Nothing from page 73 yet", what scanning adds to the list, and Scan Page 73.
struct ScanOfferPopover: View {
    let offer: ScanOffer
    var onScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing from page \(offer.page) yet")
                .font(.headline)
            Text("\(offer.bookTitle) has nothing scanned from page \(offer.page). Scanning it adds “\(offer.title)” to the book's list if it isn't there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Scan Page \(offer.page)", systemImage: "camera.viewfinder", action: onScan)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(minWidth: 220, idealWidth: 300, maxWidth: 340, alignment: .leading)
    }
}

/// A Reference opened from a pill or Related reading: the term the pointer named opens its entry.
struct OpenedReference: Identifiable {
    let id = UUID()
    let reference: Reference
    var term: String?
}
