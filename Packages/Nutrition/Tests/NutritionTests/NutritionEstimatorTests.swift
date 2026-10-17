import Testing
@testable import Nutrition

struct FixtureSource: NutritionDataSource {
    let table: [String: NutrientProfile]
    func profilePer100g(forIngredient name: String) async throws -> NutrientProfile? { table[name] }
}

@Suite("Nutrition estimator")
struct NutritionEstimatorTests {
    let source = FixtureSource(table: [
        "flour": NutrientProfile(calories: 364, proteinGrams: 10, fatGrams: 1, carbohydrateGrams: 76),
        "butter": NutrientProfile(calories: 717, proteinGrams: 1, fatGrams: 81, carbohydrateGrams: 0),
    ])

    @Test func dividesTotalsBetweenServings() async throws {
        let estimator = NutritionEstimator(source: source)
        let estimate = try await estimator.estimate(
            [WeighedIngredient(name: "flour", grams: 200), WeighedIngredient(name: "butter", grams: 100)],
            servings: 4
        )
        #expect(abs(estimate.perServing.calories - (364 * 2 + 717) / 4) < 0.001)
        #expect(abs(estimate.perServing.fatGrams - (1 * 2 + 81) / 4) < 0.001)
        #expect(estimate.confidence == 1)
        #expect(estimate.unmatchedIngredients.isEmpty)
    }

    @Test func reportsUnmatchedMassAsLowerConfidence() async throws {
        let estimator = NutritionEstimator(source: source)
        let estimate = try await estimator.estimate(
            [WeighedIngredient(name: "flour", grams: 300), WeighedIngredient(name: "unicorn", grams: 100)],
            servings: 1
        )
        #expect(abs(estimate.confidence - 0.75) < 0.001)
        #expect(estimate.unmatchedIngredients == ["unicorn"])
    }

    @Test func rejectsZeroServings() async {
        let estimator = NutritionEstimator(source: source)
        await #expect(throws: NutritionError.noServings) {
            try await estimator.estimate([], servings: 0)
        }
    }

    @Test func unconfiguredFDCClientThrows() async {
        await #expect(throws: NutritionError.sourceNotConfigured) {
            try await FoodDataCentralClient().profilePer100g(forIngredient: "flour")
        }
    }
}
