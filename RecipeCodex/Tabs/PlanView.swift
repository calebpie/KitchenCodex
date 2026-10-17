import SwiftUI

/// Events, menus, shopping lists and schedules. Phases 4 and 5.
struct PlanView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No events planned", systemImage: "calendar")
            } description: {
                Text("Create an event to build a menu, a shopping list and a workback schedule.")
            }
            .navigationTitle("Plan")
        }
    }
}

#Preview {
    PlanView()
}
