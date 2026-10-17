import Foundation
import RecipeModel

/// How the Recipes view lays out the library (More → View as).
enum RecipeLayout: String, CaseIterable, Identifiable {
    case grid, list

    var id: Self { self }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

/// Library sort order (More → Sort By).
enum RecipeSort: String, CaseIterable, Identifiable {
    case title, recentlyAdded

    var id: Self { self }

    var title: String {
        switch self {
        case .title: "Title"
        case .recentlyAdded: "Recently Added"
        }
    }

    var descriptors: [SortDescriptor<Recipe>] {
        switch self {
        case .title: [SortDescriptor(\Recipe.title, comparator: .localizedStandard)]
        case .recentlyAdded: [SortDescriptor(\Recipe.createdAt, order: .reverse)]
        }
    }
}

/// The Cooked state chip.
enum CookedFilter: String, CaseIterable, Identifiable {
    case any, neverCooked, cooked

    var id: Self { self }

    var title: String {
        switch self {
        case .any: "Any"
        case .neverCooked: "Never Cooked"
        case .cooked: "Cooked"
        }
    }
}

/// The library's view filter. Not a search: search is the Search tab (03 §3.2).
/// This slice has Course and Cooked state; Cuisine, Time, Dietary, Book and Tags come later in Phase 1.
struct RecipeFilter: Equatable {
    var course: String?
    var cooked: CookedFilter = .any

    var isActive: Bool { course != nil || cooked != .any }

    func matches(_ recipe: Recipe) -> Bool {
        if let course, recipe.course != course { return false }
        switch cooked {
        case .any: return true
        case .neverCooked: return recipe.isNeverCooked
        case .cooked: return !recipe.isNeverCooked
        }
    }
}

/// Courses offered when entering a recipe and in the Course chip. Stored on `Recipe.course` as plain
/// text, so imports can bring other values; the chip lists those too.
enum RecipeCourse {
    static let standard = [
        "Breakfast", "Starter", "Soup", "Salad", "Main", "Side",
        "Dessert", "Bread", "Sauce", "Drink", "Snack",
    ]

    /// The standard courses followed by any others found in the library.
    static func options(including recipes: [Recipe]) -> [String] {
        let extra = Set(recipes.compactMap(\.course)).subtracting(standard).sorted()
        return standard + extra
    }
}

extension RecipeVersion {
    /// "1 hr 30 min", for cards and rows.
    var displayTime: String? {
        displayMinutes.map { Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) }
    }
}
