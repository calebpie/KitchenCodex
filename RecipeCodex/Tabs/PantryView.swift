import RecipeModel
import SwiftData
import SwiftUI

/// Everything you have to cook with (03 §3.17), as a hub (04 §5.1 Pantry hub): one row per pane,
/// Staples · Tools · Cellar & Bar · Sources, each with a live summary, and Profile as the hub's
/// toolbar button. On iPad the same rows are the sidebar, with Profile at its foot. There is no
/// Kitchens pane: one implicit Home kitchen sits behind the panes and is never shown (04 §5.1
/// Kitchens). Phase 1 fills Profile; Phase 4 fills the panes.
struct PantryView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case staples = "Staples"
        case tools = "Tools"
        case cellarAndBar = "Cellar & Bar"
        case sources = "Sources"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .staples: "basket"
            case .tools: "oven"
            case .cellarAndBar: "wineglass"
            case .sources: "storefront"
            }
        }

        var emptyDescription: String {
            switch self {
            case .staples: "Staples you keep on hand. The shopping list subtracts what is here."
            case .tools: "Ovens, burners, mixers and pots. The schedule plans around them."
            case .cellarAndBar: "Wine and spirits on hand, so pairings know what is already in the house."
            case .sources: "Stores you frequent and specialty suppliers, including those listed in your cookbooks."
            }
        }
    }

    /// What the hub pushes, or the iPad sidebar shows in the detail column.
    enum Destination: Hashable {
        case pane(Pane)
        case profile
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone: the pushed pane or Profile.
    @State private var path: [Destination] = []
    /// iPad: the sidebar's selection.
    @State private var selection: Destination? = .pane(.staples)

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List(selection: $selection) {
                    PantryHubRows()
                }
                .navigationTitle("Pantry")
                // Profile sits at the sidebar's foot, where Notes and Reminders put the sidebar's
                // own control, so the top bar holds only the system's sidebar toggle. A trailing
                // item there also made the column reserve the tab bar's height as a white band.
                .toolbar {
                    profileButton(placement: .bottomBar, isShown: selection == .profile) { selection = .profile }
                }
            } detail: {
                NavigationStack {
                    if let selection {
                        destination(selection)
                    } else {
                        destination(.pane(.staples))
                    }
                }
            }
        } else {
            NavigationStack(path: $path) {
                List {
                    PantryHubRows()
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Pantry")
                .navigationDestination(for: Destination.self) { destination($0) }
                .toolbar { profileButton(placement: .primaryAction) { path.append(.profile) } }
            }
        }
    }

    /// The only profile button in the app (04 §5.1 Pantry hub): the standard account glyph at the
    /// hub's trailing edge, or at the foot of the iPad sidebar, filled while Profile is shown there
    /// since no sidebar row is selected then.
    private func profileButton(placement: ToolbarItemPlacement, isShown: Bool = false, action: @escaping () -> Void) -> some ToolbarContent {
        ToolbarItem(placement: placement) {
            Button("Profile", systemImage: isShown ? "person.crop.circle.fill" : "person.crop.circle", action: action)
                .accessibilityAddTraits(isShown ? .isSelected : [])
        }
    }

    @ViewBuilder
    private func destination(_ destination: Destination) -> some View {
        switch destination {
        case .profile:
            ProfilePane()
                .navigationTitle("Profile")
        case let .pane(pane):
            // Add (+) and More (⋯) arrive on each pane with its content (Phase 4).
            ContentUnavailableView {
                Label(pane.rawValue, systemImage: pane.symbol)
            } description: {
                Text(pane.emptyDescription)
            }
            .navigationTitle(pane.rawValue)
        }
    }
}

/// One row per pane with its symbol, name and a summary of what is in it ("3 staples · 1 out",
/// "12 bottles"), or "Nothing yet". Rows push their pane on iPhone and select it on iPad.
private struct PantryHubRows: View {
    @Query private var staples: [PantryItem]
    @Query private var tools: [Tool]
    @Query private var bottles: [BeverageItem]
    @Query private var sources: [Source]

    var body: some View {
        Section {
            ForEach(PantryView.Pane.allCases) { pane in
                NavigationLink(value: PantryView.Destination.pane(pane)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pane.rawValue)
                            Text(summary(for: pane))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: pane.symbol)
                    }
                }
                .tag(PantryView.Destination.pane(pane))
            }
        }
    }

    private func summary(for pane: PantryView.Pane) -> String {
        switch pane {
        case .staples:
            let kept = staples.filter(\.isStaple)
            guard !kept.isEmpty else { return "Nothing yet" }
            let out = kept.count { !$0.isInStock }
            let count = kept.count == 1 ? "1 staple" : "\(kept.count) staples"
            return out == 0 ? count : "\(count) · \(out) out"
        case .tools:
            return counted(tools.count, "tool", "tools")
        case .cellarAndBar:
            return counted(bottles.reduce(0) { $0 + $1.bottles }, "bottle", "bottles")
        case .sources:
            return counted(sources.count, "source", "sources")
        }
    }

    private func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        switch count {
        case 0: "Nothing yet"
        case 1: "1 \(singular)"
        default: "\(count) \(plural)"
        }
    }
}

#Preview {
    PantryView()
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
