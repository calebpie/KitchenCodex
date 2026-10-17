import SwiftUI

/// Everything you have to cook with (03 §3.17): ingredients, tools, sources, cellar and bar,
/// kitchens, and your profile. Phase 1 fills Profile; Phase 4 fills the rest.
struct PantryView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case pantry = "Pantry"
        case tools = "Tools"
        case sources = "Sources"
        case cellarAndBar = "Cellar & Bar"
        case kitchens = "Kitchens"
        case profile = "Profile"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .pantry: "cabinet"
            case .tools: "frying.pan"
            case .sources: "storefront"
            case .cellarAndBar: "wineglass"
            case .kitchens: "house"
            case .profile: "person.crop.circle"
            }
        }

        var emptyDescription: String {
            switch self {
            case .pantry: "Staples you keep on hand. The shopping list subtracts what is here."
            case .tools: "Ovens, burners, mixers and pots. The schedule plans around them."
            case .sources: "Stores you frequent and specialty suppliers, including those listed in your cookbooks."
            case .cellarAndBar: "Wine and spirits on hand, so pairings know what is already in the house."
            case .kitchens: "Home and anywhere else you cook, each with its own tools and pantry."
            case .profile: "Proficiency, units, voice, the kitchen theme and model settings."
            }
        }
    }

    @State private var pane: Pane = .pantry

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(pane.rawValue, systemImage: pane.symbol)
            } description: {
                Text(pane.emptyDescription)
            }
            .navigationTitle("Pantry")
            .safeAreaInset(edge: .top) {
                // A scrolling pane selector in the Recipes filter-chip style (03 §3.17).
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Pane.allCases) { candidate in
                            Button(candidate.rawValue) { pane = candidate }
                                .buttonStyle(.bordered)
                                .tint(candidate == pane ? .accentColor : .secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

#Preview {
    PantryView()
}
