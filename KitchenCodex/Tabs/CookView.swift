import SwiftUI

/// Today: the active cook session, tonight's plan, timers, and suggestions, and only what is
/// cooking. Review prompts for imports live in Recipes (04 §5.1 Review prompt); the rest arrives
/// with cook mode and planning.
struct CookView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Nothing on the stove", systemImage: "frying.pan")
            } description: {
                Text("Plan an event to see tonight's tasks here, or start a recipe from Recipes.")
            }
            .navigationTitle("Cook")
        }
    }
}

#Preview {
    CookView()
}
