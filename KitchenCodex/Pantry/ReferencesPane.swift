import RecipeModel
import SwiftData
import SwiftUI

/// Pantry → References (03 §3.17, 04 §5.1 "References home"): technique chapters and glossaries
/// scanned from a book and articles saved from the web, grouped by book with the web articles
/// together, each opening its page. Swipe to delete. A reference asked for from outside (Spotlight,
/// a link) opens as a sheet over the list.
struct ReferencesPane: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Reference.title, comparator: .localizedStandard)]) private var references: [Reference]
    @State private var requested: Reference?
    /// The page pushed from a row. A binding, not a `NavigationLink(value:)`: the iPhone's Pantry
    /// stack has a typed path (`PantryView.Destination`), which ignores a value of another type.
    @State private var opened: Reference?

    private var books: [(book: Book, references: [Reference])] {
        let grouped = Dictionary(grouping: references.filter { $0.book != nil }, by: { $0.book! })
        return grouped.map { book, found in
            (book, found.sorted { ($0.source?.firstPage ?? $0.bookEntry?.page ?? .max, $0.title) < ($1.source?.firstPage ?? $1.bookEntry?.page ?? .max, $1.title) })
        }
        .sorted { $0.book.displayTitle.localizedStandardCompare($1.book.displayTitle) == .orderedAscending }
    }

    private var web: [Reference] { references.filter { $0.book == nil } }

    var body: some View {
        Group {
            if references.isEmpty {
                ContentUnavailableView {
                    Label("References", systemImage: PantryView.Pane.references.symbol)
                } description: {
                    Text(PantryView.Pane.references.emptyDescription)
                }
            } else {
                List {
                    ForEach(books, id: \.book.persistentModelID) { group in
                        Section(group.book.displayTitle) {
                            ForEach(group.references) { reference in
                                row(reference)
                            }
                        }
                    }
                    if !web.isEmpty {
                        Section("From the Web") {
                            ForEach(web) { reference in
                                row(reference)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("References")
        .navigationDestination(item: $opened) { reference in
            ReferencePageView(reference: reference) { recipe in router.openRecipe(id: recipe.id) }
        }
        .sheet(item: $requested) { reference in
            ReferenceSheet(reference: reference)
        }
        .onChange(of: router.requestedReferenceID, initial: true) { _, id in
            guard let id else { return }
            router.requestedReferenceID = nil
            requested = references.first { $0.id == id }
        }
    }

    private func row(_ reference: Reference) -> some View {
        Button {
            opened = reference
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference.title.isEmpty ? "Reference" : reference.title)
                    Text(subtitle(reference))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .tint(.primary)
        .accessibilityHint("Opens the reference.")
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                ReferenceSaving.delete(reference, in: modelContext)
            }
        }
    }

    /// "Chapter · p. 250", "Chapter · pp. 250–253 · 12 entries", "Article · seriouseats.com".
    private func subtitle(_ reference: Reference) -> String {
        var parts = [reference.kind.word]
        if reference.book != nil {
            if let first = reference.source?.firstPage, let last = reference.source?.lastPage, last != first {
                parts.append("pp. \(first)–\(last)")
            } else if let page = reference.source?.firstPage ?? reference.bookEntry?.page {
                parts.append("p. \(page)")
            }
        } else {
            parts.append(reference.sourceLine)
        }
        let count = reference.sortedSections.count
        if count > 1 { parts.append(reference.sortedSections.allSatisfy { !$0.heading.isEmpty } ? "\(count) entries" : "\(count) sections") }
        return parts.joined(separator: " · ")
    }
}
