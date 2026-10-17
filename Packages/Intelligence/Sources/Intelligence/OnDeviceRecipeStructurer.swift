import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Structures a page's visible text (or OCR text) into a recipe with Apple's on-device model.
///
/// Used only when the deterministic readers come up short (04 §1): Capture asks for it through
/// `RecipeStructuring`, checks `isAvailable` first, and keeps its own result when this throws.
/// The model is told to copy lines rather than rewrite them, so the ingredient parser still reads
/// the amounts.
public struct OnDeviceRecipeStructurer: RecipeStructuring {
    /// Confidence reported for a model reading. Below the import review threshold on purpose:
    /// a model-read recipe is always worth a look (03 §1, trustworthy intelligence).
    public static let reportedConfidence = 0.6

    public init() {}

    public var isAvailable: Bool {
        if case .success = ModelAvailability.onDevice() { return true }
        return false
    }

    public func structure(_ text: String) async throws -> StructuredRecipeDraft {
        #if canImport(FoundationModels)
        guard isAvailable else {
            if case let .failure(error) = ModelAvailability.onDevice() { throw error }
            throw ModelUnavailabilityError(reason: .unknown)
        }
        let model = SystemLanguageModel.default
        // Leave room for the instructions, the schema and the answer, which can be as long as the input.
        let characterBudget = max(2_000, Int(Double(model.contextSize) * 1.4))
        let pageText = String(text.prefix(characterBudget))

        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let response = try await session.respond(
            to: "Page text:\n\n\(pageText)",
            generating: GeneratedRecipe.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        let recipe = response.content
        return StructuredRecipeDraft(
            title: recipe.title.trimmingCharacters(in: .whitespacesAndNewlines),
            ingredients: recipe.ingredients.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            steps: recipe.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            confidence: Self.reportedConfidence
        )
        #else
        throw ModelUnavailabilityError(reason: .notConfigured)
        #endif
    }

    static let instructions = """
        You read recipe web pages. The text was copied from a page and may include menus, ads, \
        stories and comments around the recipe. Find the one recipe and return its title, every \
        ingredient line and every instruction step, in the page's order. Copy ingredient lines \
        exactly as written, keeping amounts and units. Copy steps in the page's words; do not \
        summarize, invent or add anything that is not on the page.
        """
}

#if canImport(FoundationModels)
@Generable(description: "A recipe copied from a web page")
struct GeneratedRecipe {
    @Guide(description: "The recipe's name, without the site's name")
    var title: String

    @Guide(description: "Every ingredient line in order, exactly as written, with its amount and unit")
    var ingredients: [String]

    @Guide(description: "Every instruction step in order, in the page's words")
    var steps: [String]
}
#endif
