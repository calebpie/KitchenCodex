import Capture
import RecipeModel
import SwiftData
import SwiftUI

/// One pointer's card in review's banner (03 §3.6, 02 Flow C step 6): what the page is in the
/// book, and Link to existing recipe (the book's recipe from that page first, else a picker over
/// the library) · Add to this book's to-scan list · Ignore. A page the book's list has as a recipe,
/// or that reads as one, is a recipe; another goes on the list as reference reading (04 §5.1 "Page
/// pointers"). The answer is kept in the review and applied when it is saved.
struct PointerCard: View {
    let pointer: ReviewPointer
    let book: Book?
    /// The recipe under review again, which can't be its own component.
    var stored: Recipe?
    var onChoose: (PointerChoice) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isPicking = false

    private var reading: CrossReferenceLinking.Reading? {
        book.map { CrossReferenceLinking.read(pointer.reference, from: stored, in: $0, state: BookScanStore.shared.state(for: $0)) }
    }

    var body: some View {
        let reading = reading
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: reading?.isReference == true ? "book.pages" : "arrow.turn.down.right")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(pointer.reference.target.map { "\($0) · \(phrase)" } ?? phrase)
                    .font(.subheadline.weight(.semibold))
            }
            Text(explanation(reading))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { choices(reading) }
                VStack(alignment: .leading, spacing: 8) { choices(reading) }
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $isPicking) {
            RecipePickerSheet(excluding: stored) { recipe in onChoose(.link(recipe.id)) }
        }
    }

    /// The pointer as printed, without its parentheses.
    private var phrase: String {
        pointer.reference.phrase.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
    }

    private func explanation(_ reading: CrossReferenceLinking.Reading?) -> String {
        guard let book, let reading else {
            return "A page from no book: link it to a recipe in your library, or ignore it."
        }
        if case let .link(id) = pointer.choice, let linked = recipe(id) {
            return "Linked to “\(linked.title)”: it shows under Includes."
        }
        guard let page = reading.page else {
            return "The recipe it names isn't in \(book.displayTitle) yet."
        }
        if pointer.reference.pages.isEmpty {
            return reading.suggested.map { "“\($0.title)” follows it in \(book.displayTitle)." } ?? "The recipe it names follows on this page or the next."
        }
        if let suggested = reading.suggested {
            return "Page \(page) is “\(suggested.title)” in \(book.displayTitle)."
        }
        if reading.isReference {
            switch pointer.reference.kind {
            case .sources: return "Page \(page) is the book's Sources page: reference reading for the to-scan list."
            case .technique: return "Page \(page) describes a technique: reference reading for the to-scan list."
            default: return "Page \(page) isn't a recipe on \(book.displayTitle)'s list, so it goes on the to-scan list as reference reading."
            }
        }
        if let listed = reading.listed {
            return "Page \(page) is “\(listed.displayTitle)” on the list, not scanned yet."
        }
        return "Page \(page) holds a recipe not scanned yet."
    }

    @ViewBuilder
    private func choices(_ reading: CrossReferenceLinking.Reading?) -> some View {
        if let suggested = reading?.suggested {
            Menu {
                Button("Link to Another Recipe…", systemImage: "magnifyingglass") { isPicking = true }
            } label: {
                chip("Link to “\(suggested.title)”", isSelected: isLinked)
            } primaryAction: {
                onChoose(.link(suggested.id))
            }
            .accessibilityHint("Makes it a component of this recipe.")
        } else {
            Button { isPicking = true } label: {
                chip(isLinked ? "Linked to “\(linkedID.flatMap(recipe)?.title ?? "a recipe")”" : "Link to Existing Recipe…", isSelected: isLinked)
            }
            .buttonStyle(.plain)
        }
        // A page whose recipe the book already has needs no place on the list.
        if book != nil, let reading, reading.page != nil, reading.suggested == nil {
            Button { onChoose(.addToList) } label: {
                chip(reading.isReference ? "Add to To-Scan List as Reference" : "Add to To-Scan List", isSelected: pointer.choice == .addToList)
            }
            .buttonStyle(.plain)
        }
        Button { onChoose(.ignore) } label: {
            chip("Ignore", isSelected: pointer.choice == .ignore)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Leaves the pointer as words; the pill still opens the page.")
    }

    private var linkedID: UUID? {
        if case let .link(id) = pointer.choice { id } else { nil }
    }

    private var isLinked: Bool { linkedID != nil }

    private func recipe(_ id: UUID) -> Recipe? {
        try? modelContext.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })).first
    }

    private func chip(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(isSelected ? AnyShapeStyle(Color.indigo) : AnyShapeStyle(Color.indigo.opacity(0.15)), in: .capsule)
            .contentShape(.capsule)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The library to pick a component from: every recipe but the one under review, by title, with a
/// search field.
struct RecipePickerSheet: View {
    var excluding: Recipe?
    var onPick: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Recipe.title, comparator: .localizedStandard)]) private var recipes: [Recipe]
    @State private var query = ""

    private var shown: [Recipe] {
        let others = recipes.filter { $0 != excluding }
        guard !query.trimmed.isEmpty else { return others }
        return others.filter { $0.title.localizedStandardContains(query.trimmed) || $0.sourceLine.localizedStandardContains(query.trimmed) }
    }

    var body: some View {
        NavigationStack {
            List(shown) { recipe in
                Button {
                    onPick(recipe)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.title).foregroundStyle(.primary)
                        Text(recipe.sourceLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No Recipes" : "No Matches", systemImage: "magnifyingglass")
                }
            }
            .searchable(text: $query, prompt: "Recipes")
            .navigationTitle("Link to Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}
