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
            Reference(title: "Brown Butter", kind: .technique), ReferenceSection(heading: "Why it works", body: "…"),
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

    /// 04 §5.1 Ingredient lines: a note, its form, and the produce it counts, stored beside the item.
    @Test func ingredientKeepsNoteAndEquivalent() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let juice = Ingredient(item: "orange juice", rawText: "5 ounces (142 ml) orange juice (about 3 oranges)")
        juice.note = "about 3 oranges"
        juice.noteForm = "parenthetical"
        juice.equivalentCountNumerator = 3
        juice.equivalentCountDenominator = 1
        juice.equivalentItem = "oranges"
        let pear = Ingredient(item: "pear juice", rawText: "1 cup pear juice (about 1 ½ pears)")
        pear.note = "about 1 1/2 pears"
        pear.equivalentCountNumerator = 3
        pear.equivalentCountDenominator = 2
        pear.equivalentItem = "pears"
        let salt = Ingredient(item: "kosher salt", rawText: "1 tsp kosher salt")
        let flour = Ingredient(item: "all-purpose flour", rawText: "3 1/2 cups all-purpose flour, plus extra (for kneading)")
        flour.note = "plus extra (for kneading)"
        flour.noteForm = "clause"
        for model in [juice, pear, salt, flour] as [any PersistentModel] { context.insert(model) }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Ingredient>(sortBy: [SortDescriptor(\.item)]))
        #expect(fetched.map(\.item) == ["all-purpose flour", "kosher salt", "orange juice", "pear juice"])
        #expect(fetched[0].noteForm == "clause")
        let fetchedSalt = fetched[1]
        #expect(fetchedSalt.note == nil && fetchedSalt.noteForm == nil && fetchedSalt.equivalentItem == nil && fetchedSalt.equivalentCountNumerator == nil)
        let fetchedJuice = fetched[2]
        #expect(fetchedJuice.note == "about 3 oranges" && fetchedJuice.noteForm == "parenthetical")
        #expect(fetchedJuice.equivalentItem == "oranges")
        #expect(fetched[3].equivalentCountNumerator == 3 && fetched[3].equivalentCountDenominator == 2)
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

    /// A reference keeps its book, its sections in order, its source (book and pages) and the
    /// recipes it informs, both ways. Deleting it takes its sections, source and images and leaves
    /// the book and recipes.
    @Test func referenceLinksBookRecipesAndSource() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let book = Book(title: "A Bistro Book")
        let entry = BookEntry(title: "The Importance of Brown Butter", page: 171)
        let fish = Recipe(title: "Skate with Brown Butter")
        let gnocchi = Recipe(title: "Gnocchi")
        let reference = Reference(title: "The Importance of Brown Butter", author: "A. Chef", kind: .technique)
        reference.tags = ["butter", "sauce"]
        let opening = ReferenceSection(heading: "", body: "Opening text.", sortOrder: 0)
        let method = ReferenceSection(heading: "Method", body: "Method text.", sortOrder: 1)
        let source = SourceInfo()
        source.captureMethod = .scan
        source.firstPage = 171
        source.lastPage = 172
        let scan = RecipeImage(role: .pageScan, imageData: Data([0xFF, 0xD8]))
        scan.pageKind = .reference
        for model in [book, entry, fish, gnocchi, reference, opening, method, source, scan] as [any PersistentModel] { context.insert(model) }
        reference.book = book
        reference.bookEntry = entry
        reference.sections = [method, opening]
        reference.source = source
        reference.images = [scan]
        reference.recipes = [fish, gnocchi]
        scan.book = book
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Reference>()).first)
        #expect(fetched.kind == .technique && fetched.tags == ["butter", "sauce"])
        #expect(fetched.sections?.sorted { $0.sortOrder < $1.sortOrder }.map(\.heading) == ["", "Method"])
        #expect(fetched.source?.firstPage == 171 && fetched.source?.lastPage == 172 && fetched.source?.captureMethod == .scan)
        #expect(book.references?.map(\.title) == ["The Importance of Brown Butter"])
        #expect(book.pageScans?.count == 1)
        #expect(entry.reference?.title == "The Importance of Brown Butter")
        #expect(fish.references?.map(\.title) == ["The Importance of Brown Butter"])
        #expect(Set(fetched.recipes?.map(\.title) ?? []) == ["Skate with Brown Butter", "Gnocchi"])
        #expect(source.reference?.title == fetched.title)

        context.delete(fetched)
        try context.save()
        #expect(try count(of: ReferenceSection.self, in: context) == 0)
        #expect(try count(of: SourceInfo.self, in: context) == 0)
        #expect(try count(of: RecipeImage.self, in: context) == 0)
        #expect(try count(of: Recipe.self, in: context) == 2)
        #expect(try count(of: Book.self, in: context) == 1)
        #expect(fish.references?.isEmpty == true)
        #expect(entry.reference == nil)
    }

    /// A page scan keeps its review regions as JSON, its page kind and its book; a scanned recipe its
    /// extraction confidence, how it came in, its pages, its review reasons.
    @Test func pageScanKeepsRegionsAndProvenance() throws {
        let container = try RecipeStore.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let book = Book(title: "A Bistro Book")
        let recipe = Recipe(title: "Roast Chicken")
        recipe.extractionConfidence = 0.82
        let version = RecipeVersion()
        version.needsReview = true
        version.reviewReasons = ["firstRecipeOfBook", "unparsedIngredients"]
        let source = SourceInfo()
        source.captureMethod = .photo
        source.firstPage = 12
        let scan = RecipeImage(role: .pageScan, imageData: Data([0xFF, 0xD8]))
        scan.pageNumber = 12
        scan.pageKind = .recipe
        let regions = ScanRegions(layoutSignature: "c2 t:center", pageNumber: 12, regions: [
            ScanRegion(kind: "heading", role: "title", x: 0.1, y: 0.2, width: 0.6, height: 0.03, text: "Roast Chicken", confidence: 0.9),
            ScanRegion(kind: "line", role: "ingredient", x: 0.1, y: 0.3, width: 0.2, height: 0.01, text: "1 chicken", confidence: 0.8, item: 0),
            ScanRegion(kind: "photo", x: 0.5, y: 0.6, width: 0.3, height: 0.2),
        ])
        scan.regions = try regions.encoded()
        let contents = RecipeImage(role: .pageScan, imageData: Data([0xFF, 0xD8, 0x02]))
        contents.pageKind = .contents
        let queued = RecipeImage(role: .pageScan, imageData: Data([0xFF, 0xD8, 0x03]))
        for model in [book, recipe, version, source, scan, contents, queued] as [any PersistentModel] { context.insert(model) }
        recipe.book = book
        recipe.addVersion(version)
        recipe.source = source
        recipe.images = [scan]
        scan.book = book
        contents.book = book
        queued.book = book
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(fetched.extractionConfidence == 0.82)
        #expect(fetched.currentVersion?.reviewReasons == ["firstRecipeOfBook", "unparsedIngredients"])
        #expect(fetched.source?.captureMethod == .photo && fetched.source?.reviewedAt == nil)
        let image = try #require(fetched.images?.first)
        #expect(ScanRegions.decoded(from: image.regions) == regions)
        #expect(image.pageKind == .recipe && image.book?.title == "A Bistro Book")
        #expect(Set(book.pageScans?.map(\.pageKind) ?? []) == [.recipe, .contents, nil])
        #expect(ScanRegions.decoded(from: nil) == nil)
        #expect(ScanRegions.decoded(from: Data("not json".utf8)) == nil)

        // Deleting the book leaves its recipes and their scans.
        context.delete(book)
        try context.save()
        #expect(try count(of: Recipe.self, in: context) == 1)
        #expect(try count(of: RecipeImage.self, in: context) == 3)
        #expect(image.book == nil)
    }

    /// 02 §4.2: every relationship optional with an inverse, no unique constraints,
    /// defaults on non-optional attributes, images in external storage.
    @Test func followsCloudKitRules() throws {
        let schema = RecipeStore.schema
        let entitiesByName = Dictionary(uniqueKeysWithValues: schema.entities.map { ($0.name, $0) })

        // Phase 2's schema change (slice 2) is present, so the loop below checks it too.
        let phase2: [String: [String]] = [
            "Reference": ["title", "author", "kind", "capturedAt", "tags", "book", "bookEntry", "recipes", "sections", "source", "images"],
            "ReferenceSection": ["heading", "body", "sortOrder", "reference"],
            "Recipe": ["extractionConfidence", "references"],
            "RecipeVersion": ["reviewReasons"],
            "RecipeImage": ["regions", "pageKind", "book", "reference"],
            "SourceInfo": ["captureMethod", "firstPage", "lastPage", "reviewedAt", "reference"],
            "Book": ["references", "pageScans"],
            "BookEntry": ["reference"],
        ]
        for (entityName, names) in phase2 {
            let entity = try #require(entitiesByName[entityName], "missing entity \(entityName)")
            let present = Set(entity.attributes.map(\.name) + entity.relationships.map(\.name))
            for name in names {
                #expect(present.contains(name), "missing \(entityName).\(name)")
            }
        }
        for (entityName, name) in [("Recipe", "extractionConfidence"), ("RecipeImage", "regions"), ("RecipeImage", "pageKind"),
                                   ("SourceInfo", "captureMethod"), ("SourceInfo", "firstPage"), ("SourceInfo", "reviewedAt")] {
            let attribute = entitiesByName[entityName]?.attributes.first { $0.name == name }
            #expect(attribute?.isOptional == true, "\(entityName).\(name) must be optional")
        }

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
