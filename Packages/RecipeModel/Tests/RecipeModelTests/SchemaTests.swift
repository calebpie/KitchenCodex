import Foundation
import SwiftData
import Testing
@testable import RecipeModel

@Suite("Schema v1")
struct SchemaTests {
    @Test func containerBuildsInMemory() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        #expect(container.schema.entities.count == RecipeSchemaV1.models.count)
    }

    @Test func insertsOneOfEachModel() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let instances: [any PersistentModel] = [
            Book(title: "Six Seasons"), BookSection(title: "Spring"), BookEntry(title: "Peas", page: 12),
            Recipe(title: "Roast Chicken"), RecipeVersion(), Ingredient(item: "chicken", rawText: "1 whole chicken"),
            Step(text: "Salt it."), RecipeLink(), Tag(name: "weeknight"), CookSession(), SourceInfo(),
            NutritionEstimate(), RecipeImage(role: .pageScan, imageData: Data([0xFF, 0xD8])),
            Event(name: "Sunday Supper", guestCount: 8), Guest(name: "Rosa", restrictions: ["gluten-free"]),
            EventMenu(), Slot(name: "Main"), Candidate(servings: 8), ShoppingList(), ShoppingItem(normalizedIngredient: "chicken"),
            Schedule(), ScheduleTask(title: "Brine", durationMinutes: 20),
            Kitchen(isDefault: true), Tool(type: "oven", name: "Wall oven"), PantryItem(item: "kosher salt"), UserProfile(),
        ]
        #expect(instances.count == RecipeSchemaV1.models.count)

        for instance in instances { context.insert(instance) }
        try context.save()

        for modelType in RecipeSchemaV1.models {
            #expect(try count(of: modelType, in: context) == 1, "expected one \(modelType)")
        }
    }

    @Test func relationshipsRoundTrip() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let recipe = Recipe(title: "Focaccia")
        let version = RecipeVersion()
        let flour = Ingredient(item: "flour", rawText: "500 g flour")
        flour.quantityNumerator = 500
        flour.quantityDenominator = 1
        flour.unit = "gram"
        context.insert(recipe)
        context.insert(version)
        context.insert(flour)
        recipe.versions = [version]
        recipe.currentVersion = version
        version.ingredients = [flour]
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Recipe>()).first
        #expect(fetched?.currentVersion?.ingredients?.first?.item == "flour")
        #expect(fetched?.currentVersion?.recipe?.title == "Focaccia")
        #expect(fetched?.currentVersion?.isCurrentOf?.title == "Focaccia")
    }

    /// 02 §4.2: every relationship optional with an inverse, no unique constraints,
    /// defaults on non-optional attributes, images in external storage.
    @Test func followsCloudKitRules() throws {
        let schema = RecipeStore.schema
        let entitiesByName = Dictionary(uniqueKeysWithValues: schema.entities.map { ($0.name, $0) })

        for entity in schema.entities {
            for relationship in entity.relationships {
                let label = "\(entity.name).\(relationship.name)"
                #expect(relationship.isOptional, "\(label) must be optional")
                #expect(relationship.deleteRule != .deny, "\(label) must not use .deny")

                let hasInverse = relationship.inverseName != nil
                    || entitiesByName[relationship.destination]?.relationships.contains { $0.inverseName == relationship.name } == true
                #expect(hasInverse, "\(label) needs an inverse")
            }

            for attribute in entity.attributes {
                let label = "\(entity.name).\(attribute.name)"
                #expect(!attribute.isUnique, "\(label) must not be unique")
                if !attribute.isOptional {
                    #expect(attribute.defaultValue != nil, "\(label) needs a default value")
                }
                if attribute.name.hasSuffix("ImageData") || attribute.name == "imageData" {
                    #expect(attribute.options.contains(.externalStorage), "\(label) must use external storage")
                }
            }
        }
    }

    private func count<T: PersistentModel>(of type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}
