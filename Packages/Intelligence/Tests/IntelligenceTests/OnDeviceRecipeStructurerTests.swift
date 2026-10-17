import Foundation
import Testing
@testable import Intelligence

@Suite("On-device recipe structurer")
struct OnDeviceRecipeStructurerTests {
    /// Hand-written, as a page's visible text would arrive: navigation, a story, then the recipe.
    static let pageText = """
        Home Recipes Shop
        Weeknight Lemon Pasta
        We make this every Tuesday when the lemons are good.
        Ingredients
        12 ounces spaghetti
        2 lemons, zested and juiced
        4 tablespoons butter
        1/2 cup grated parmesan
        Kosher salt
        Directions
        Boil the spaghetti in well-salted water until al dente; reserve 1 cup of the water.
        Melt the butter with the lemon zest, add the pasta, juice, parmesan and enough water to make it glossy.
        Comments (12)
        """

    @Test func availabilityIsAnAnswerNotACrash() {
        // The test host may or may not have Apple Intelligence; either way the check must be total
        // and agree with ModelAvailability.
        let structurer = OnDeviceRecipeStructurer()
        switch ModelAvailability.onDevice() {
        case .success: #expect(structurer.isAvailable)
        case .failure: #expect(!structurer.isAvailable)
        }
    }

    @Test func throwsWhenTheModelIsUnavailable() async {
        guard !OnDeviceRecipeStructurer().isAvailable else { return }
        await #expect(throws: ModelUnavailabilityError.self) {
            try await OnDeviceRecipeStructurer().structure(Self.pageText)
        }
    }

    /// Runs the real model only where it exists (a Mac or simulator with Apple Intelligence on).
    @Test(.enabled(if: OnDeviceRecipeStructurer().isAvailable, "On-device model not available on this host"),
          .timeLimit(.minutes(2)))
    func readsAPageWithTheModel() async throws {
        let draft = try await OnDeviceRecipeStructurer().structure(Self.pageText)
        #expect(draft.title.localizedCaseInsensitiveContains("lemon"))
        #expect(draft.ingredients.count >= 4)
        #expect(draft.ingredients.contains { $0.contains("spaghetti") })
        #expect(draft.steps.count >= 2)
        #expect(draft.confidence == OnDeviceRecipeStructurer.reportedConfidence)
    }

    @Test func protocolDefaultsToAvailable() {
        #expect(DeterministicRecipeStructurer().isAvailable)
    }
}
