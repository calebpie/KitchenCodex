import Foundation
import Testing
@testable import Capture

/// "Split into N recipes" (04 §2, ux-notes row 61): which ingredient groups and step groups line up.
/// The recipes are made up; the fixture pages' plans are in the private harness's report.
@Suite("Component split")
struct ComponentSplitTests {
    /// Each line's group, from runs of (heading, count).
    static func groups(_ runs: [(String?, Int)]) -> [String?] {
        runs.flatMap { Array(repeating: $0.0, count: $0.1) }
    }

    @Test func pairsLabelledStepsWithTheirGroupsByName() throws {
        let plan = try #require(ComponentSplit.plan(
            title: "Grilled Lamb with Two Pickles",
            ingredientGroups: Self.groups([("For the lamb", 4), ("For the quick-pickled shallots", 3), ("For the pickled radishes", 3), ("To serve", 2)]),
            steps: [
                "Marinate the lamb: Whisk the oil and garlic, coat the chops and chill for 2 hours.",
                "Pickle the radishes: Slice them thin and pour the warm brine over.",
                "Pickle the shallots: Ring them and cover with the vinegar.",
                "Heat a grill pan over high heat.",
                "Grill the chops for 4 minutes a side.",
            ]
        ))
        // Names decide, so the radishes take the second label though their group comes third.
        #expect(plan.parts.map(\.title) == ["Lamb", "Quick-Pickled Shallots", "Pickled Radishes"])
        #expect(plan.parts.map(\.steps) == [[0], [2, 3, 4], [1]])
        #expect(plan.parts.map(\.ingredients) == [[0, 1, 2, 3], [4, 5, 6], [7, 8, 9]])
        // The lamb is the dish the title names; the pickles it comes with are components.
        #expect(plan.parts.map(\.isComponent) == [false, true, true])
        // "To serve" has no label; its lines stay with the parent.
        #expect(plan.parent(choosing: [1, 2]) == (ingredients: [0, 1, 2, 3, 10, 11], steps: [0]))
        #expect(plan.defaultRecipeCount == 3)
    }

    @Test func aServingLabelClosesTheRunBeforeIt() throws {
        let plan = try #require(ComponentSplit.plan(
            title: "Tian of Summer Vegetables",
            ingredientGroups: Self.groups([("Pepper Sauce", 3), ("Vegetables", 3), ("Dressing", 2)]),
            steps: [
                "For the pepper sauce: Roast the peppers until blistered.",
                "Simmer the sauce until thick.",
                "For the vegetables: Slice everything thin and shingle it over the sauce.",
                "Bake covered for 2 hours.",
                "For the dressing: Whisk the vinegar and oil.",
                "To serve: Warm the tian and spoon the dressing around it.",
            ]
        ))
        #expect(plan.parts.map(\.steps) == [[0, 1], [2, 3], [4]])
        #expect(plan.parent(choosing: Set(plan.parts.indices)).steps == [5])
    }

    @Test func asManyLabelsAsGroupsPairInOrder() throws {
        // No label shares a word with its group; the counts and the order decide.
        let plan = try #require(ComponentSplit.plan(
            title: "Braised Beans",
            ingredientGroups: Self.groups([("Marinade", 3), ("Sauce", 3)]),
            steps: ["Soak the beans: Cover them with cold water overnight.", "Simmer the tomatoes: Cook them down with the garlic."]
        ))
        #expect(plan.parts.map(\.steps) == [[0], [1]])
    }

    @Test func aGroupWithNoLabelStartsAtTheStepThatNamesIt() throws {
        // A scanned page: the method's headings went to the ingredient groups, and every group's
        // method ends with the same label, which marks no boundary.
        let plan = try #require(ComponentSplit.plan(
            title: "Vegetables in a Spiced Broth",
            ingredientGroups: Self.groups([(nil, 5), ("Baby Leeks", 2), ("Turnips", 2), ("Carrots", 2)]),
            steps: [
                "Combine the broth ingredients and bring to a simmer.",
                "Trim the leeks and halve them lengthwise.",
                "Poach in the broth until tender.",
                "TO FINISH: Warm through and season.",
                "Peel the turnips and cut into wedges.",
                "TO FINISH: Warm through and season.",
                "Scrub the carrots and cut on the bias.",
                "Poach until just tender.",
                "TO FINISH: Warm through and season.",
            ]
        ))
        #expect(plan.parts.map(\.title) == ["Baby Leeks", "Turnips", "Carrots"])
        #expect(plan.parts.map(\.steps) == [[1, 2, 3], [4, 5], [6, 7, 8]])
        // The broth, which no heading names, stays with the parent.
        #expect(plan.parent(choosing: Set(plan.parts.indices)) == (ingredients: [0, 1, 2, 3, 4], steps: [0]))
    }

    @Test func servingAndContinuingGroupsStayWithTheParent() throws {
        let plan = try #require(ComponentSplit.plan(
            title: "Baked Pasta",
            ingredientGroups: Self.groups([("Making the Meat Sauce", 3), ("Making the White Sauce", 3), ("Finishing the Meat Sauce", 1), ("Assembling the Bake", 2)]),
            steps: [
                "To make the meat sauce, brown the beef and add the tomatoes.",
                "To make the white sauce, melt the butter and whisk in the flour.",
                "The meat sauce is done when most of the liquid is gone.",
                "Before assembling the bake, heat the oven.",
            ]
        ))
        #expect(plan.parts.map(\.isComponent) == [true, true, false, false])
        #expect(plan.parts.map(\.steps) == [[0], [1], [2], [3]])
        #expect(plan.defaultRecipeCount == 3)
    }

    @Test func aParentLeftEmptyKeepsTheDishItself() throws {
        let plan = try #require(ComponentSplit.plan(
            title: "Beef Braised in Red Wine",
            ingredientGroups: Self.groups([("For the braise", 4), ("For the glazed onions", 2), ("For the mushrooms", 2)]),
            steps: [
                "Brown the beef in batches and braise for 3 hours.",
                "Skim the sauce.",
                "For the glazed onions, simmer them in stock until glazed.",
                "For the mushrooms, sauté them in butter.",
            ]
        ))
        #expect(plan.parts.map(\.isComponent) == [false, true, true])
        #expect(plan.parent(choosing: [1, 2]).steps == [0, 1])
    }

    @Test func offersNothingWhenTheGroupsDoNotLineUp() {
        // One group only.
        #expect(ComponentSplit.plan(title: "Soup", ingredientGroups: Self.groups([("For the soup", 4)]), steps: ["Chop.", "Simmer."]) == nil)
        // Groups no step names or starts.
        #expect(ComponentSplit.plan(title: "Cake", ingredientGroups: Self.groups([("Dry", 3), ("Wet", 3)]), steps: ["Heat the oven.", "Mix it all and bake."]) == nil)
        // One group that would run to the end, leaving the parent its lines and no steps.
        #expect(ComponentSplit.plan(title: "Lentil Soup", ingredientGroups: Self.groups([("Stock", 3), (nil, 4)]),
                                    steps: ["Begin with the stock.", "Strain it.", "Add the lentils.", "Simmer until soft."]) == nil)
        // Only serving groups line up.
        #expect(ComponentSplit.plan(title: "Tacos", ingredientGroups: Self.groups([(nil, 4), ("To serve", 3)]), steps: ["Cook the filling.", "To serve: Warm the tortillas."]) == nil)
    }

    @Test func titlesComponentsFromTheirHeadings() {
        #expect(ComponentSplit.componentTitle("For the onion and jalapeño pickle") == "Onion and Jalapeño Pickle")
        #expect(ComponentSplit.componentTitle("BABY LEEKS") == "Baby Leeks")
        #expect(ComponentSplit.componentTitle("Making the Green Pasta Dough") == "Green Pasta Dough")
        #expect(ComponentSplit.componentTitle("To make the dressing:") == "Dressing")
        #expect(ComponentSplit.componentTitle("Vinaigrette") == "Vinaigrette")
    }

    @Test func readsNamedSectionsFromJSONLD() throws {
        let json = """
        {"@context": "https://schema.org", "@type": "Recipe", "name": "Fish with Salsa Verde",
         "recipeIngredient": ["2 fillets", "Salt", "1 bunch parsley", "2 anchovies"],
         "recipeInstructions": [
           {"@type": "HowToSection", "name": "Cook the fish", "itemListElement": [
             {"@type": "HowToStep", "text": "Salt the fish."}, {"@type": "HowToStep", "text": "Roast at 400°F."},
             {"@type": "HowToStep", "text": "Tip: Use a thermometer."}]},
           {"@type": "HowToSection", "name": "Make the salsa verde", "itemListElement": [
             {"@type": "HowToStep", "text": "Chop the parsley and anchovies together."}]}
         ]}
        """
        var recipe = try JSONLDRecipeParser.parse(Data(json.utf8), sourceURL: nil)
        #expect(recipe.stepGroups == [0: "Cook the fish", 3: "Make the salsa verde"])
        // An aside moved to the notes leaves the next section where its first step now is.
        recipe.movingAsidesToNotes()
        #expect(recipe.steps.map(\.text) == ["Salt the fish.", "Roast at 400°F.", "Chop the parsley and anchovies together."])
        #expect(recipe.stepGroups == [0: "Cook the fish", 2: "Make the salsa verde"])
        // With groups on the ingredients, the sections pair with them by name.
        recipe.ingredientGroups = [0: "For the fish", 2: "For the salsa verde"]
        let plan = try #require(recipe.splitPlan)
        #expect(plan.parts.map(\.steps) == [[0, 1], [2]])
        #expect(plan.parts.map(\.isComponent) == [false, true])
    }
}
