import Foundation
import Intelligence
import Units

/// Macronutrients per 100 g, or per serving once scaled.
public struct NutrientProfile: Sendable, Codable, Equatable {
    public var calories: Double
    public var proteinGrams: Double
    public var fatGrams: Double
    public var carbohydrateGrams: Double

    public init(calories: Double, proteinGrams: Double, fatGrams: Double, carbohydrateGrams: Double) {
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.carbohydrateGrams = carbohydrateGrams
    }

    public static let zero = NutrientProfile(calories: 0, proteinGrams: 0, fatGrams: 0, carbohydrateGrams: 0)

    public func scaled(by factor: Double) -> NutrientProfile {
        NutrientProfile(
            calories: calories * factor,
            proteinGrams: proteinGrams * factor,
            fatGrams: fatGrams * factor,
            carbohydrateGrams: carbohydrateGrams * factor
        )
    }

    public static func + (lhs: NutrientProfile, rhs: NutrientProfile) -> NutrientProfile {
        NutrientProfile(
            calories: lhs.calories + rhs.calories,
            proteinGrams: lhs.proteinGrams + rhs.proteinGrams,
            fatGrams: lhs.fatGrams + rhs.fatGrams,
            carbohydrateGrams: lhs.carbohydrateGrams + rhs.carbohydrateGrams
        )
    }
}

/// An ingredient line resolved to a mass, ready for lookup.
public struct WeighedIngredient: Sendable, Equatable {
    public var name: String
    public var grams: Double
    public init(name: String, grams: Double) {
        self.name = name
        self.grams = grams
    }
}

/// Per-serving estimate with the confidence the UI shows beside it.
public struct NutritionEstimate: Sendable, Equatable {
    public var perServing: NutrientProfile
    /// Share of ingredient mass that was matched to a data source, 0...1.
    public var confidence: Double
    public var unmatchedIngredients: [String]
}

/// Where per-100 g profiles come from. USDA FoodData Central in production; fixtures in tests.
public protocol NutritionDataSource: Sendable {
    func profilePer100g(forIngredient name: String) async throws -> NutrientProfile?
}

public enum NutritionError: Error, Equatable {
    case noServings
    case sourceNotConfigured
}

/// Sums ingredient profiles and divides by servings. Ingredient-name normalization
/// through Intelligence is a Phase 3 addition; today names are matched as given.
public struct NutritionEstimator: Sendable {
    public var source: any NutritionDataSource

    public init(source: any NutritionDataSource) {
        self.source = source
    }

    public func estimate(_ ingredients: [WeighedIngredient], servings: Int) async throws -> NutritionEstimate {
        guard servings > 0 else { throw NutritionError.noServings }
        var total = NutrientProfile.zero
        var matchedGrams = 0.0
        var unmatched: [String] = []
        for ingredient in ingredients {
            if let per100 = try await source.profilePer100g(forIngredient: ingredient.name) {
                total = total + per100.scaled(by: ingredient.grams / 100)
                matchedGrams += ingredient.grams
            } else {
                unmatched.append(ingredient.name)
            }
        }
        let totalGrams = ingredients.reduce(0) { $0 + $1.grams }
        return NutritionEstimate(
            perServing: total.scaled(by: 1 / Double(servings)),
            confidence: totalGrams > 0 ? matchedGrams / totalGrams : 0,
            unmatchedIngredients: unmatched
        )
    }
}

/// USDA FoodData Central client. Phase 3 implements search and caching; today it only records the key.
public struct FoodDataCentralClient: NutritionDataSource {
    public var apiKey: String?

    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    public func profilePer100g(forIngredient name: String) async throws -> NutrientProfile? {
        guard apiKey != nil else { throw NutritionError.sourceNotConfigured }
        return nil
    }
}
