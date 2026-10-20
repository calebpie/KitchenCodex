import RecipeModel
import SwiftData
import SwiftUI

/// The kinds of filter the Filter list offers, one row each (04 §5.1 Recipes filters, ux-notes row 41).
enum RecipeFilterKind: String, CaseIterable, Identifiable {
    case course = "Course"
    case cooked = "Cooked"
    case favorites = "Favorites"
    case needsReview = "Needs a Look"
    case collection = "Collection"
    case cookbook = "Cookbook"
    case tag = "Tag"

    var id: Self { self }

    /// Favorites and Needs a Look are on or off: toggle rows, and tokens that read only their name.
    var isToggle: Bool { self == .favorites || self == .needsReview }
}

/// What the Filter list can offer: the courses the library uses, and the collections (iPhone
/// only; the iPad sidebar selects them), cookbooks and tags that exist.
struct RecipeFilterOptions {
    var courses: [String] = []
    var collections: [(id: PersistentIdentifier, name: String)] = []
    var books: [(id: PersistentIdentifier, name: String)] = []
    var tags: [(id: PersistentIdentifier, name: String)] = []

    /// The rows of the list's first level, in order; a kind with nothing to choose is left out.
    var kinds: [RecipeFilterKind] {
        RecipeFilterKind.allCases.filter { kind in
            switch kind {
            case .course: !courses.isEmpty
            case .cooked, .favorites, .needsReview: true
            case .collection: !collections.isEmpty
            case .cookbook: !books.isEmpty
            case .tag: !tags.isEmpty
            }
        }
    }

    /// The values a list kind offers, by id and name.
    func values(for kind: RecipeFilterKind) -> [(id: String, name: String)] {
        switch kind {
        case .course: courses.map { ($0, $0) }
        case .cooked: [CookedFilter.neverCooked, .cooked].map { ($0.rawValue, $0.title) }
        case .collection: collections.map { (Self.key($0.id), $0.name) }
        case .cookbook: books.map { (Self.key($0.id), $0.name) }
        case .tag: tags.map { (Self.key($0.id), $0.name) }
        case .favorites, .needsReview: []
        }
    }

    fileprivate static func key(_ id: PersistentIdentifier) -> String { String(describing: id) }
}

extension RecipeFilter {
    /// What `kind` is set to, as the list's detail text and the token read it ("Main, Side",
    /// "The Food Lab"), "" for a toggle that is on, nil when the kind isn't set. Names come from
    /// `options`, with a fallback for one that has gone.
    func selection(of kind: RecipeFilterKind, options: RecipeFilterOptions) -> String? {
        switch kind {
        case .course:
            guard !courses.isEmpty else { return nil }
            // Standard order first, then any course no longer offered.
            let ordered = options.courses.filter(courses.contains) + courses.subtracting(options.courses).sorted()
            return ordered.joined(separator: ", ")
        case .cooked:
            return cooked == .any ? nil : cooked.title
        case .favorites:
            return favorites ? "" : nil
        case .needsReview:
            return needsReview ? "" : nil
        case .collection:
            return collection.map { id in options.collections.first { $0.id == id }?.name ?? "Collection" }
        case .cookbook:
            return book.map { id in options.books.first { $0.id == id }?.name ?? "Cookbook" }
        case .tag:
            return tag.map { id in options.tags.first { $0.id == id }?.name ?? "Tag" }
        }
    }

    /// The token under the title: "Course: Main, Side", "Cookbook: The Food Lab", "Favorites".
    /// Cooked reads its value alone ("Never Cooked", "Cooked"), as the switches read their names
    /// (ux-notes row 46).
    func token(for kind: RecipeFilterKind, options: RecipeFilterOptions) -> String? {
        guard let selection = selection(of: kind, options: options) else { return nil }
        if kind.isToggle { return kind.rawValue }
        return kind == .cooked ? selection : "\(kind.rawValue): \(selection)"
    }

    /// Clears one kind; the token's ×.
    mutating func clear(_ kind: RecipeFilterKind) {
        switch kind {
        case .course: courses = []
        case .cooked: cooked = .any
        case .favorites: favorites = false
        case .needsReview: needsReview = false
        case .collection: collection = nil
        case .cookbook: book = nil
        case .tag: tag = nil
        }
    }

    fileprivate func isSelected(_ value: String, of kind: RecipeFilterKind) -> Bool {
        switch kind {
        case .course: courses.contains(value)
        case .cooked: cooked.rawValue == value
        case .collection: collection.map(RecipeFilterOptions.key) == value
        case .cookbook: book.map(RecipeFilterOptions.key) == value
        case .tag: tag.map(RecipeFilterOptions.key) == value
        case .favorites, .needsReview: false
        }
    }

    /// A tap on a value: courses add and remove, several at once; the others take one value, and
    /// a tap on the chosen one clears it.
    fileprivate mutating func toggle(_ value: String, of kind: RecipeFilterKind, options: RecipeFilterOptions) {
        let id = { (items: [(id: PersistentIdentifier, name: String)]) in
            items.first { RecipeFilterOptions.key($0.id) == value }?.id
        }
        let isOn = !isSelected(value, of: kind)
        switch kind {
        case .course:
            if isOn { courses.insert(value) } else { courses.remove(value) }
        case .cooked:
            cooked = isOn ? CookedFilter(rawValue: value) ?? .any : .any
        case .collection:
            collection = isOn ? id(options.collections) : nil
        case .cookbook:
            book = isOn ? id(options.books) : nil
        case .tag:
            tag = isOn ? id(options.tags) : nil
        case .favorites, .needsReview:
            break
        }
    }
}

/// The Filter list (04 §5.1 Recipes filters, ux-notes row 41): a popover from the Filter button
/// on iPad, a sheet on iPhone, and the menu bar's View → Filter… opens the same. One row per kind
/// with its selection as the detail; a row opens its values with checkmarks, Back returns to the
/// list, Done (or Escape) closes it, Clear All at the foot. Changes apply as they are made.
struct RecipeFilterList: View {
    @Binding var filter: RecipeFilter
    let options: RecipeFilterOptions

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(options.kinds) { kind in
                        if kind.isToggle {
                            Toggle(kind.rawValue, isOn: binding(for: kind))
                        } else {
                            NavigationLink(value: kind) {
                                LabeledContent(kind.rawValue, value: filter.selection(of: kind, options: options) ?? "Any")
                            }
                        }
                    }
                }
                Section {
                    Button("Clear All", role: .destructive) {
                        withAnimation { filter = RecipeFilter() }
                    }
                    .disabled(!filter.isActive)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RecipeFilterKind.self) { kind in
                FilterValuesList(kind: kind, filter: $filter, options: options) { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private func binding(for kind: RecipeFilterKind) -> Binding<Bool> {
        switch kind {
        case .needsReview: $filter.needsReview
        default: $filter.favorites
        }
    }
}

/// One kind's values with checkmarks (several for Course), pushed over the list; Back returns.
private struct FilterValuesList: View {
    let kind: RecipeFilterKind
    @Binding var filter: RecipeFilter
    let options: RecipeFilterOptions
    /// Closes the popover or sheet, not just this page.
    var onDone: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(options.values(for: kind), id: \.id) { value in
                    let isSelected = filter.isSelected(value.id, of: kind)
                    Button {
                        filter.toggle(value.id, of: kind, options: options)
                    } label: {
                        HStack {
                            // The label color, not the button's tint; the checkmark carries the tint.
                            Text(value.name)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            } footer: {
                if kind == .course {
                    Text("Recipes in any of the checked courses.")
                }
            }
        }
        .navigationTitle(kind.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", role: .confirm, action: onDone)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}
