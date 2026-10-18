import RecipeModel
import SwiftData
import SwiftUI

/// Everything you have to cook with (03 §3.17): ingredients, tools, sources, cellar and bar,
/// kitchens, and your profile. Phase 1 fills Profile (`ProfilePane`); Phase 4 fills the rest.
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
            Group {
                switch pane {
                case .profile:
                    ProfilePane()
                default:
                    ContentUnavailableView {
                        Label(pane.rawValue, systemImage: pane.symbol)
                    } description: {
                        Text(pane.emptyDescription)
                    }
                }
            }
            .navigationTitle("Pantry")
            // A bar, not a plain inset, so a scrolling pane passes under it with the scroll edge effect.
            .safeAreaBar(edge: .top) {
                // A scrolling pane selector in the Recipes filter-chip style (03 §3.17).
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Pane.allCases) { candidate in
                                Button(candidate.rawValue) { pane = candidate }
                                    .buttonStyle(.bordered)
                                    .tint(candidate == pane ? .accentColor : .secondary)
                                    .id(candidate)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    // Keep the selected pane's chip in view; the bar is rebuilt when the pane's
                    // content changes between a scroll view and a static view.
                    .onAppear { proxy.scrollTo(pane, anchor: .center) }
                    .onChange(of: pane) { _, selected in
                        withAnimation { proxy.scrollTo(selected, anchor: .center) }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }
}

#Preview {
    PantryView()
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
