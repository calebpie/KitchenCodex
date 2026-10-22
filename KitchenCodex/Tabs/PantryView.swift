import RecipeModel
import SwiftData
import SwiftUI

/// Everything you have to cook with (03 §3.17), as a hub (04 §5.1 Pantry hub): one row per pane,
/// Staples · Tools · Cellar & Bar · Sources · References (04 §5.1 "References home"), each with the
/// pane's purpose until it has content and a live summary after. On iPhone a row pushes its pane and Profile is the hub's toolbar button.
/// On iPad the panes are the system sidebar's Pantry section and Profile its bottom-bar button
/// (RootTabView), and this tab's page stays the hub, whose rows select those sidebar tabs. There is
/// no Kitchens pane: one implicit Home kitchen sits behind the panes and is never shown (04 §5.1
/// Kitchens). Phase 1 fills Profile; Phase 4 fills the panes.
struct PantryView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case staples = "Staples"
        case tools = "Tools"
        case cellarAndBar = "Cellar & Bar"
        case sources = "Sources"
        case references = "References"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .staples: "basket"
            case .tools: "oven"
            case .cellarAndBar: "wineglass"
            case .sources: "storefront"
            case .references: "text.book.closed"
            }
        }

        /// What the pane is for, naming the benefit: the hub row's second line while the pane is
        /// empty, and the pane's own placeholder. Short enough for two lines in a narrow column.
        var emptyDescription: String {
            switch self {
            case .staples: "Ingredients on hand, so the shopping list skips them."
            case .tools: "Ovens, burners and pots, so the schedule plans around them."
            case .cellarAndBar: "Wine and spirits in the house, so pairings know what's here."
            case .sources: "Stores and suppliers, your favorites first."
            case .references: "Technique chapters and articles, kept beside the recipes they inform."
            }
        }
    }

    /// What the iPhone hub pushes.
    enum Destination: Hashable {
        case pane(Pane)
        case profile
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppRouter.self) private var router
    /// iPhone: the pushed pane or Profile.
    @State private var path: [Destination] = []

    var body: some View {
        if sizeClass == .regular {
            // iPad: the hub's rows select the sidebar's pane tabs; Profile is in the sidebar's
            // bottom bar, so the hub has no toolbar button.
            NavigationStack {
                List {
                    PantryHubRows { pane in router.selectedTab = .pantryPane(pane) }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Pantry")
            }
        } else {
            NavigationStack(path: $path) {
                List {
                    PantryHubRows()
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Pantry")
                .navigationDestination(for: Destination.self) { destination($0) }
                .toolbar {
                    // The only profile button on iPhone (04 §5.1 Pantry hub): the standard account
                    // glyph at the hub's trailing edge.
                    ToolbarItem(placement: .primaryAction) {
                        Button("Profile", systemImage: "person.crop.circle") { path.append(.profile) }
                    }
                }
            }
            // A reference asked for from outside (Spotlight, a link, a saved article): the
            // References pane, which opens it.
            .onChange(of: router.requestedReferenceID, initial: true) { _, id in
                guard id != nil, path.last != .pane(.references) else { return }
                path = [.pane(.references)]
            }
        }
    }

    @ViewBuilder
    private func destination(_ destination: Destination) -> some View {
        switch destination {
        case .profile:
            ProfilePane()
                .navigationTitle("Profile")
        case let .pane(pane):
            PantryPaneView(pane: pane)
        }
    }
}

/// One pane: pushed from the iPhone hub, or an iPad sidebar tab of its own.
struct PantryPaneView: View {
    let pane: PantryView.Pane

    var body: some View {
        switch pane {
        case .references:
            ReferencesPane()
        case .sources:
            SourcesPane()
        default:
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

/// One row per pane with its symbol, name and a second line (04 §5.1 Pantry hub): what the pane is
/// for while it is empty, then a summary of what is in it ("3 staples · 1 out", "12 bottles").
/// Rows push their pane on iPhone; on iPad, given `onSelect`, they select the pane's sidebar tab.
private struct PantryHubRows: View {
    /// iPad: shows the pane in its sidebar tab instead of pushing it.
    var onSelect: ((PantryView.Pane) -> Void)?

    @Query private var staples: [PantryItem]
    @Query private var tools: [Tool]
    @Query private var bottles: [BeverageItem]
    @Query private var sources: [Source]
    @Query private var references: [Reference]

    var body: some View {
        Section {
            ForEach(PantryView.Pane.allCases) { pane in
                if let onSelect {
                    Button {
                        onSelect(pane)
                    } label: {
                        HStack {
                            label(for: pane)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .tint(.primary)
                } else {
                    NavigationLink(value: PantryView.Destination.pane(pane)) {
                        label(for: pane)
                    }
                }
            }
        }
    }

    private func label(for pane: PantryView.Pane) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.rawValue)
                Text(summary(for: pane) ?? pane.emptyDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: pane.symbol)
        }
    }

    /// What is in the pane, or nil while it is empty.
    private func summary(for pane: PantryView.Pane) -> String? {
        switch pane {
        case .staples:
            let kept = staples.filter(\.isStaple)
            guard !kept.isEmpty else { return nil }
            let out = kept.count { !$0.isInStock }
            let count = kept.count == 1 ? "1 staple" : "\(kept.count) staples"
            return out == 0 ? count : "\(count) · \(out) out"
        case .tools:
            return counted(tools.count, "tool", "tools")
        case .cellarAndBar:
            return counted(bottles.reduce(0) { $0 + $1.bottles }, "bottle", "bottles")
        case .sources:
            return counted(sources.count, "source", "sources")
        case .references:
            // "4 chapters · 2 articles" (04 §5.1 "References home").
            let parts = [ReferenceKind.chapter, .technique, .article, .clipping].compactMap { kind -> String? in
                let count = references.count { $0.kind == kind }
                return count == 0 ? nil : (count == 1 ? "1 \(kind.word.lowercased())" : "\(count) \(kind.plural)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    private func counted(_ count: Int, _ singular: String, _ plural: String) -> String? {
        switch count {
        case 0: nil
        case 1: "1 \(singular)"
        default: "\(count) \(plural)"
        }
    }
}

#Preview {
    PantryView()
        .environment(AppRouter())
        .environment(SyncMonitor(store: .inMemory(reason: "Preview")))
        .modelContainer(try! RecipeStore.makeContainer(inMemory: true))
}
