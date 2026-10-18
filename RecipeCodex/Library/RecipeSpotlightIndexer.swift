import CoreSpotlight
import Foundation
import OSLog
import RecipeModel
import SwiftData
import UniformTypeIdentifiers

/// Keeps the library in Spotlight (02 §1: recipes are indexed entities): each recipe's title, its
/// ingredients and where it came from, with the cover as the thumbnail. Tapping a result opens the
/// app with `CSSearchableItemActionType`, which RootTabView hands to Recipes.
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
        let removed = previous.keys.filter { current[$0] == nil }.map(\.uuidString)

        var items: [CSSearchableItem] = []
        for recipe in changed {
            items.append(await Self.item(for: recipe))
        }

        do {
            if isFirstSync {
                try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
            } else if !removed.isEmpty {
                try await index.deleteSearchableItems(withIdentifiers: removed)
            }
            if !items.isEmpty {
                try await index.indexSearchableItems(items)
            }
            indexed = current
            logger.info("Spotlight: indexed \(items.count) recipes\(isFirstSync ? " after clearing the index" : ", removed \(removed.count)")")
        } catch {
            logger.error("Spotlight indexing failed: \(error.localizedDescription)")
        }
    }

    /// One recipe as a Spotlight item: title; the source and time as the description; ingredients as
    /// keywords and searchable text.
    static func item(for recipe: Recipe) async -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = recipe.title
        attributes.displayName = recipe.title

        let version = recipe.currentVersion
        let ingredients = version?.sortedIngredients ?? []
        let source = recipe.sourceLine
        var description = [source]
        if let time = version?.displayTime { description.append(time) }
        if let course = recipe.course { description.append(course) }
        attributes.contentDescription = description.joined(separator: " · ")

        let items = ingredients.map(\.item).filter { !$0.isEmpty }
        attributes.textContent = ingredients.map(\.rawText).joined(separator: "\n")
        var keywords = items
        keywords += [recipe.course, recipe.cuisine, recipe.source?.siteName, recipe.source?.author, recipe.book?.title].compactMap(\.self)
        attributes.keywords = keywords
        if let author = recipe.source?.author { attributes.authorNames = [author] }
        if let url = recipe.source?.url { attributes.url = url }
        attributes.addedDate = recipe.createdAt
        attributes.contentModificationDate = recipe.updatedAt

        if let cover = recipe.coverImageData {
            attributes.thumbnailData = await ImageProcessing.jpeg(from: cover, maxPixelSize: 240, quality: 0.8)
        }

        let item = CSSearchableItem(uniqueIdentifier: recipe.id.uuidString, domainIdentifier: domainIdentifier, attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
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
