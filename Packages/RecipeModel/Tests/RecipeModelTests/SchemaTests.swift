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
            NutritionEstimate(), RecipeImage(role: .pageScan, imageData: Data([0xFF, 0xD8])), RecipeCollection(name: "Sunday Suppers"),
            Event(name: "Sunday Supper", guestCount: 8), Guest(name: "Rosa", restrictions: ["gluten-free"]),
            EventMenu(), Slot(name: "Main"), Candidate(servings: 8), Pairing(role: .wine, text: "a dry Riesling"),
            ShoppingList(), ShoppingItem(normalizedIngredient: "chicken"),
            Schedule(), ScheduleTask(title: "Brine", durationMinutes: 20),
            Kitchen(isDefault: true), Tool(type: "oven", name: "Wall oven"), PantryItem(item: "kosher salt"),
            Source(name: "D'Artagnan", kind: .online, categories: [.food]), BeverageItem(kind: .wine, name: "Chablis", bottles: 2),
            UserProfile(),
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

    /// 04 §5.1 Ingredient lines: a note, and the produce it counts, stored beside the item.
    @Test func ingredientKeepsNoteAndEquivalent() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let juice = Ingredient(item: "orange juice", rawText: "5 ounces (142 ml) orange juice (about 3 oranges)")
        juice.note = "about 3 oranges"
        juice.equivalentCountNumerator = 3
        juice.equivalentCountDenominator = 1
        juice.equivalentItem = "oranges"
        let pear = Ingredient(item: "pear juice", rawText: "1 cup pear juice (about 1 ½ pears)")
        pear.note = "about 1 1/2 pears"
        pear.equivalentCountNumerator = 3
        pear.equivalentCountDenominator = 2
        pear.equivalentItem = "pears"
        let salt = Ingredient(item: "kosher salt", rawText: "1 tsp kosher salt")
        for model in [juice, pear, salt] as [any PersistentModel] { context.insert(model) }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Ingredient>(sortBy: [SortDescriptor(\.item)]))
        #expect(fetched.map(\.item) == ["kosher salt", "orange juice", "pear juice"])
        #expect(fetched[0].note == nil && fetched[0].equivalentItem == nil && fetched[0].equivalentCountNumerator == nil)
        #expect(fetched[1].note == "about 3 oranges")
        #expect(fetched[1].equivalentItem == "oranges")
        #expect(fetched[2].equivalentCountNumerator == 3 && fetched[2].equivalentCountDenominator == 2)
    }

    /// Pairings live on the menu and can point at a bottle in the cellar (03 §3.9, §3.17).
    @Test func pairingLinksSlotAndCellar() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let kitchen = Kitchen(isDefault: true)
        let bottle = BeverageItem(kind: .wine, name: "Chablis", bottles: 2)
        let slot = Slot(name: "Starter")
        let pairing = Pairing(role: .wine, text: "")
        let mocktail = Pairing(role: .nonAlcoholic, text: "ginger and lime spritz")
        for model in [kitchen, bottle, slot, pairing, mocktail] as [any PersistentModel] { context.insert(model) }
        kitchen.beverages = [bottle]
        slot.pairings = [pairing, mocktail]
        pairing.beverage = bottle
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Slot>()).first
        #expect(fetched?.pairings?.count == 2)
        #expect(fetched?.pairings?.first { $0.role == .wine }?.beverage?.name == "Chablis")
        #expect(bottle.pairings?.count == 1)
        #expect(bottle.kitchen?.isDefault == true)
    }

    /// A step photo links both ways; one from the source has no cook session. Deleting the step
    /// deletes its photos, and deleting a photo leaves the step.
    @Test func stepPhotoLinksBothWays() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let version = RecipeVersion()
        let step = Step(text: "Truss the duck.", sortOrder: 0)
        let first = RecipeImage(role: .stepPhoto, imageData: Data([0xFF, 0xD8]))
        let second = RecipeImage(role: .stepPhoto, imageData: Data([0xFF, 0xD8, 0x01]))
        for model in [version, step, first, second] as [any PersistentModel] { context.insert(model) }
        version.steps = [step]
        first.step = step
        second.step = step
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Step>()).first
        #expect(fetched?.images?.count == 2)
        #expect(fetched?.images?.allSatisfy { $0.role == .stepPhoto && $0.cookSession == nil } == true)
        #expect(first.step?.text == "Truss the duck.")

        context.delete(second)
        try context.save()
        #expect(try count(of: Step.self, in: context) == 1)
        #expect(step.images?.count == 1)

        context.delete(step)
        try context.save()
        #expect(try count(of: RecipeImage.self, in: context) == 0)
    }

    /// A recipe can sit in several collections and a collection holds many recipes. Deleting a
    /// collection leaves its recipes; deleting a recipe takes it out of its collections.
    @Test func collectionsHoldRecipesBothWays() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let supper = RecipeCollection(name: "Sunday Suppers", sortOrder: 0)
        let weeknight = RecipeCollection(name: "Weeknights", sortOrder: 1)
        let chicken = Recipe(title: "Roast Chicken")
        let soup = Recipe(title: "Leek Soup")
        for model in [supper, weeknight, chicken, soup] as [any PersistentModel] { context.insert(model) }
        chicken.toggleMembership(in: supper)
        chicken.toggleMembership(in: weeknight)
        soup.toggleMembership(in: weeknight)
        try context.save()

        #expect(chicken.collections?.count == 2)
        #expect(Set(weeknight.recipes?.map(\.title) ?? []) == ["Roast Chicken", "Leek Soup"])
        #expect(supper.recipes?.map(\.title) == ["Roast Chicken"])
        #expect(RecipeCollection.nextSortOrder(after: [supper, weeknight]) == 2)

        chicken.toggleMembership(in: weeknight)
        try context.save()
        #expect(!chicken.isIn(weeknight))
        #expect(weeknight.recipes?.map(\.title) == ["Leek Soup"])

        context.delete(supper)
        try context.save()
        #expect(try count(of: Recipe.self, in: context) == 2)
        #expect(chicken.collections?.isEmpty == true)

        context.delete(soup)
        try context.save()
        #expect(weeknight.recipes?.isEmpty == true)
        #expect(try count(of: RecipeCollection.self, in: context) == 1)
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
