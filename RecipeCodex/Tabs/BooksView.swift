import SwiftUI

/// The cookbook shelf. Phase 2 adds ISBN scanning and whole-book capture.
struct BooksView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Your shelf is empty", systemImage: "books.vertical")
            } description: {
                Text("Add a cookbook by scanning its ISBN to start building its recipe list.")
            }
            .navigationTitle("Books")
        }
    }
}

#Preview {
    BooksView()
}
