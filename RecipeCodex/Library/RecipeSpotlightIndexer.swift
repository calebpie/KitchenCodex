import CoreSpotlight
import Foundation
import OSLog
import RecipeModel
import SwiftData
import UniformTypeIdentifiers

/// Keeps the library in Spotlight (02 §1: recipes are indexed entities): each recipe's title, its
/// ingredients and where it came from, with the cover as the thumbnail, plus an item per ingredient
/// so "ssamjang" finds the recipes that use it. Tapping a result opens the app with
/// `CSSearchableItemActionType`, which RootTabView hands to Recipes.
///
/// The first sync after launch clears the app's items and indexes every recipe, which also drops
/// recipes deleted on another device or by an extension. After that each save in the app reindexes
/// only the recipes whose indexed content changed and removes deleted ones. No entitlement is needed.
@MainActor
final class RecipeSpotlightIndexer {
    static let domainIdentifier = "com.calebpietrafesa.RecipeCodex.recipe"

    private let container: ModelContainer
    private let index = CSSearchableIndex.default()
    private let logger = Logger(subsystem: "com.calebpietrafesa.RecipeCodex", category: "spotlight")
    /// What was last indexed for each recipe; empty until the first sync.
    private var indexed: [UUID: Fingerprint]?
    private var pending: Task<Void, Never>?
    private var saveObserver: (any NSObjectProtocol)?

    init(container: ModelContainer) {
        self.container = container
    }

    /// Indexes the library now and after every save from here on.
    func start() {
        guard saveObserver == nil, CSSearchableIndex.isIndexingAvailable() else { return }
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync() }
        }
        scheduleSync(after: .zero)
    }

    /// Coalesces bursts of saves (a library import saves once per recipe) into one sync.
    func scheduleSync(after delay: Duration = .seconds(1)) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    private func sync() async {
        let recipes: [Recipe]
        do {
            recipes = try container.mainContext.fetch(FetchDescriptor<Recipe>())
        } catch {
            logger.error("Couldn't read recipes to index: \(error.localizedDescription)")
            return
        }

        let isFirstSync = indexed == nil
        let previous = indexed ?? [:]
        var current: [UUID: Fingerprint] = [:]
        var changed: [Recipe] = []
        for recipe in recipes {
            let fingerprint = Fingerprint(recipe)
            current[recipe.id] = fingerprint
            if previous[recipe.id] != fingerprint { changed.append(recipe) }
        }
        let removed = previous.keys.filter { current[$0] == nil }

        do {
            if isFirstSync {
                // The app indexes nothing but recipes and their ingredients.
                try await index.deleteAllSearchableItems()
            } else {
                // Removed recipes, and the ingredient items of changed ones (their lines may be fewer now).
                if !removed.isEmpty {
                    try await index.deleteSearchableItems(withIdentifiers: removed.map(\.uuidString))
                }
                let stale = (removed + changed.map(\.id)).map(Self.ingredientDomain(for:))
                if !stale.isEmpty {
                    try await index.deleteSearchableItems(withDomainIdentifiers: stale)
                }
            }
            // A batch at a time: a large library has thousands of ingredient items, each with a thumbnail.
            var count = 0
            for batch in stride(from: 0, to: changed.count, by: 20).map({ changed[$0..<min($0 + 20, changed.count)] }) {
                var items: [CSSearchableItem] = []
                for recipe in batch {
                    items += await Self.items(for: recipe)
                }
                try await index.indexSearchableItems(items)
                count += items.count
            }
            indexed = current
            logger.info("Spotlight: indexed \(changed.count) recipes (\(count) items)\(isFirstSync ? " after clearing the index" : ", removed \(removed.count)")")
        } catch {
            logger.error("Spotlight indexing failed: \(error.localizedDescription)")
        }
    }

    /// Ingredient items live in a domain per recipe, so a recipe's can be replaced or removed at once.
    static func ingredientDomain(for id: UUID) -> String {
        "\(domainIdentifier).ingredients.\(id.uuidString)"
    }

    /// The recipe ID a tapped result names: a recipe item's identifier is the ID; an ingredient
    /// item's is the ID, "/", and the ingredient's position.
    static func recipeID(fromItemIdentifier identifier: String) -> UUID? {
        UUID(uuidString: String(identifier.split(separator: "/").first ?? ""))
    }

    /// A recipe's Spotlight items: the recipe, then one per ingredient.
    ///
    /// Spotlight on iOS 27 matches a query only against what it shows, the display name (title when
    /// there is none). Keywords, alternate names and text content are indexed but never matched
    /// (Apple FB16995719, FB23635795; seen on the simulator: "ssamjang" and "mirin" found nothing).
    /// So each ingredient gets its own item, shown as "ssamjang" with "In Korean Barbecue Short Ribs"
    /// beneath and the recipe's cover, which opens the recipe. The recipe item still carries the
    /// ingredients as keywords, alternate names and text content for when Spotlight matches them.
    static func items(for recipe: Recipe) async -> [CSSearchableItem] {
        let version = recipe.currentVersion
        let ingredients = version?.sortedIngredients ?? []
        let names = ingredientNames(ingredients)
        var thumbnail: Data?
        if let cover = recipe.coverImageData {
            thumbnail = await ImageProcessing.jpeg(from: cover, maxPixelSize: 240, quality: 0.8)
        }

        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = recipe.title
        attributes.displayName = recipe.title
        var description = [recipe.sourceLine]
        if let time = version?.displayTime { description.append(time) }
        if let course = recipe.course { description.append(course) }
        attributes.contentDescription = description.joined(separator: " · ")
        attributes.alternateNames = names
        attributes.textContent = ([recipe.title] + ingredients.map(\.rawText)).joined(separator: "\n")
        var keywords = names + ingredientWords(names)
        keywords += [recipe.course, recipe.cuisine, recipe.source?.siteName, recipe.source?.author, recipe.book?.title].compactMap(\.self)
        attributes.keywords = unique(keywords)
        if let author = recipe.source?.author { attributes.authorNames = [author] }
        if let url = recipe.source?.url { attributes.url = url }
        attributes.addedDate = recipe.createdAt
        attributes.contentModificationDate = recipe.updatedAt
        attributes.thumbnailData = thumbnail

        let item = CSSearchableItem(uniqueIdentifier: recipe.id.uuidString, domainIdentifier: domainIdentifier, attributeSet: attributes)
        item.expirationDate = .distantFuture
        var items = [item]

        let usedIn = ([("In " + recipe.title)] + [recipe.source?.siteName ?? recipe.book?.title].compactMap(\.self)).joined(separator: " · ")
        for (index, name) in ingredientItemNames(names, recipeTitle: recipe.title).enumerated() {
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            let shown = name.prefix(1).uppercased() + name.dropFirst()
            attributes.title = shown
            attributes.displayName = shown
            attributes.contentDescription = usedIn
            attributes.thumbnailData = thumbnail
            attributes.addedDate = recipe.createdAt
            attributes.contentModificationDate = recipe.updatedAt
            let ingredientItem = CSSearchableItem(
                uniqueIdentifier: "\(recipe.id.uuidString)/\(index)",
                domainIdentifier: ingredientDomain(for: recipe.id),
                attributeSet: attributes
            )
            ingredientItem.expirationDate = .distantFuture
            items.append(ingredientItem)
        }
        return items
    }

    /// The ingredient names that get their own Spotlight item: not the ones every recipe has
    /// (water, salt, pepper), and not one whose words are all in the recipe's title, which the recipe
    /// item already matches.
    static func ingredientItemNames(_ names: [String], recipeTitle: String) -> [String] {
        let staples: Set<String> = [
            "water", "ice", "salt", "kosher salt", "sea salt", "fine sea salt", "flaky salt", "table salt",
            "pepper", "black pepper", "freshly ground black pepper", "salt and pepper", "kosher salt and freshly ground black pepper",
        ]
        let titleWords = Set(recipeTitle.lowercased().split { !$0.isLetter }.map(String.init))
        return names.filter { name in
            let lower = name.lowercased()
            guard !staples.contains(lower) else { return false }
            let words = lower.split { !$0.isLetter }.map(String.init)
            return !words.isEmpty && !words.allSatisfy(titleWords.contains)
        }
    }

    /// Each ingredient's name once, without parentheticals: "maltose syrup", "ssamjang", "scallions".
    static func ingredientNames(_ ingredients: [Ingredient]) -> [String] {
        let names = ingredients.map { ingredient in
            (ingredient.item.isEmpty ? ingredient.rawText : ingredient.item)
                .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;:*")))
        }
        return unique(names.filter { $0.count >= 2 && $0.count <= 60 })
    }

    /// The words of ingredient names, so a query for one word of a longer name matches it.
    static func ingredientWords(_ names: [String]) -> [String] {
        let skipped: Set<String> = ["and", "or", "of", "the", "for", "with", "plus", "fresh", "freshly", "large", "small", "medium"]
        return names.flatMap { name in
            name.split { !$0.isLetter && $0 != "-" && $0 != "'" }.map(String.init)
                .filter { $0.count >= 3 && !skipped.contains($0.lowercased()) }
        }
    }

    /// `values` without repeats, ignoring case, in order.
    static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    /// The indexed content of a recipe, to tell whether it needs indexing again.
    private struct Fingerprint: Equatable {
        let title: String
        let versionID: UUID?
        let updatedAt: Date
        let course: String?
        let coverSize: Int?
        let source: String?

        init(_ recipe: Recipe) {
            title = recipe.title
            versionID = recipe.currentVersion?.id
            updatedAt = recipe.updatedAt
            course = recipe.course
            coverSize = recipe.coverImageData?.count
            source = recipe.source?.url?.absoluteString ?? recipe.source?.siteName
        }
    }
}
