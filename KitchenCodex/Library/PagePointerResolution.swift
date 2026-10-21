import Capture
import Foundation
import RecipeModel
import SwiftData
import SwiftUI

// Page pointers resolved at display time (04 §5.1 "Page pointers", ux-notes row 74): what a book
// holds from a page, by book and page number, with no schema field. A recipe scanned from the
// page, a Reference once slice 7 captures one, or nothing yet, which offers Scan page N.

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

    /// References captured from `page` (slice 7): their entry's page, or the pages their source
    /// spans.
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

extension PagePointer {
    /// The title a to-scan entry takes from the pointer: the name it gives, else the ingredient it
    /// sits on ("Dashi (see page 17)"), else "Page 17".
    func entryTitle(item: String? = nil) -> String {
        if let target, !target.isEmpty { return target }
        if let item = item?.trimmingCharacters(in: .whitespaces), !item.isEmpty {
            return item.prefix(1).uppercased() + item.dropFirst()
        }
        return "Page \(pages.first ?? 0)"
    }
}

/// A Reference a pointer opened (slice 7 captures them): its title and sections, read-only.
struct ReferencePageView: View {
    let reference: Reference

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let book = reference.book {
                    Section {
                        Text(reference.bookEntry?.page.map { "\(book.displayTitle), p. \($0)" } ?? book.displayTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach((reference.sections ?? []).sorted { $0.sortOrder < $1.sortOrder }) { section in
                    Section(section.heading) {
                        Text(section.body)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(reference.title.isEmpty ? "Reference" : reference.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}
