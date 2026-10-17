import SwiftUI

/// Today: the active cook session, tonight's plan, timers, and suggestions. Empty state only in Phase 0.
struct CookView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Nothing on the stove", systemImage: "frying.pan")
            } description: {
                Text("Start a recipe from Recipes, or plan an event to see tonight's tasks here.")
            }
            .navigationTitle("Cook")
        }
    }
}

#Preview {
    CookView()
}
