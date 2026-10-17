import Foundation
import SwiftData
import Testing
@testable import RecipeModel

@Suite("Recipe versions")
struct VersioningTests {
    @Test func editingAddsAVersionAndMakesItCurrent() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let recipe = Recipe(title: "Focaccia")
        let first = RecipeVersion(changeSummary: "Added by hand")
        context.insert(recipe)
        context.insert(first)
        recipe.addVersion(first)
        try context.save()
        #expect(first.versionNumber == 1)
        #expect(recipe.currentVersion === first)

        let second = RecipeVersion(changeSummary: "More salt")
        context.insert(second)
        recipe.addVersion(second)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(fetched.sortedVersions.map(\.versionNumber) == [1, 2])
        #expect(fetched.currentVersion?.changeSummary == "More salt")
        #expect(fetched.currentVersion?.isCurrentOf === fetched)
        #expect(first.isCurrentOf == nil, "the old version is history, not current")
        #expect(first.recipe === fetched)
    }

    @Test func ordersIngredientsAndStepsBySortOrder() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let version = RecipeVersion()
        let salt = Ingredient(item: "salt", rawText: "salt to taste", sortOrder: 1)
        let flour = Ingredient(item: "flour", rawText: "2 cups flour", sortOrder: 0)
        for model in [version, salt, flour] as [any PersistentModel] { context.insert(model) }
        version.ingredients = [salt, flour]
        #expect(version.sortedIngredients.map(\.item) == ["flour", "salt"])
    }

    @Test func coverIsTheNewestPhotoNeverAScan() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let recipe = Recipe(title: "Tart")
        let scan = RecipeImage(role: .pageScan, imageData: Data([1]))
        let photo = RecipeImage(role: .photo, imageData: Data([2]))
        for model in [recipe, scan, photo] as [any PersistentModel] { context.insert(model) }
        recipe.images = [scan, photo]
        #expect(recipe.coverImage === photo)
    }

    @Test func displayTimeFallsBackToPrepPlusCook() {
        let version = RecipeVersion()
        #expect(version.displayMinutes == nil)
        version.prepMinutes = 15
        version.cookMinutes = 30
        #expect(version.displayMinutes == 45)
        version.totalMinutes = 60
        #expect(version.displayMinutes == 60)
    }
}
