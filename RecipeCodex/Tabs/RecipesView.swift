import SwiftUI

/// The library, with a view switch between the recipe collection and the cookbook shelf (03 §3.2, §3.7).
/// Phase 1 adds browsing, filters and collections; Phase 2 fills the Books view.
struct RecipesView: View {
    enum LibraryView: String, CaseIterable, Identifiable {
        case recipes = "Recipes"
        case books = "Books"
        var id: Self { self }
    }

    @State private var libraryView: LibraryView = .recipes

    var body: some View {
        NavigationStack {
            Group {
                switch libraryView {
                case .recipes:
                    ContentUnavailableView {
                        Label("No recipes yet", systemImage: "book.closed")
                    } description: {
                        Text("Share a recipe from Safari, scan a cookbook page, or add one by hand.")
                    }
                case .books:
                    ContentUnavailableView {
                        Label("Your shelf is empty", systemImage: "books.vertical")
                    } description: {
                        Text("Add a cookbook by scanning its ISBN to start building its recipe list.")
                    }
                }
            }
            .navigationTitle("Recipes")
            .safeAreaInset(edge: .top) {
                Picker("View", selection: $libraryView) {
                    ForEach(LibraryView.allCases) { view in
                        Text(view.rawValue).tag(view)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Contextual Add: the items follow the view (02 §1.3).
                    Menu {
                        switch libraryView {
                        case .recipes:
                            Button("Import from Web", systemImage: "link") {}
                            Button("Scan Page", systemImage: "text.viewfinder") {}
                            Button("New Recipe", systemImage: "square.and.pencil") {}
                        case .books:
                            Button("Add Book", systemImage: "barcode.viewfinder") {}
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(true) // Capture flows arrive in Phases 1 and 2.
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("Sort", systemImage: "arrow.up.arrow.down") {}
                        Button("Select", systemImage: "checkmark.circle") {}
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .disabled(true)
                }
            }
        }
    }
}

#Preview {
    RecipesView()
}
