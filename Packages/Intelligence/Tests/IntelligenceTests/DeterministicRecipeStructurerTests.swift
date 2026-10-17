import Testing
@testable import Intelligence

@Suite("Deterministic structurer")
struct DeterministicRecipeStructurerTests {
    let sample = """
    Braised Short Ribs

    Ingredients:
    4 lb bone-in short ribs
    2 cups red wine

    Method
    1. Season the ribs and sear hard.
    2) Braise at 325°F for 3 hours.
    """

    @Test func splitsTitleIngredientsAndSteps() async throws {
        let draft = try await DeterministicRecipeStructurer().structure(sample)
        #expect(draft.title == "Braised Short Ribs")
        #expect(draft.ingredients == ["4 lb bone-in short ribs", "2 cups red wine"])
        #expect(draft.steps == ["Season the ribs and sear hard.", "Braise at 325°F for 3 hours."])
        #expect(draft.confidence >= 0.8)
    }

    @Test func reportsLowConfidenceWithoutHeadings() async throws {
        let draft = try await DeterministicRecipeStructurer().structure("Just a title\nand a sentence")
        #expect(draft.title == "Just a title")
        #expect(draft.steps.isEmpty)
        #expect(draft.confidence < 0.5)
    }

    @Test func onDeviceAvailabilityReturnsAnAnswer() {
        // We cannot assume Apple Intelligence on the test host; only check that the call is total.
        switch ModelAvailability.onDevice() {
        case .success: break
        case .failure(let error): #expect(ModelUnavailability.allKnown.contains(error.reason))
        }
    }
}

private extension ModelUnavailability {
    static let allKnown: [ModelUnavailability] = [
        .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .notConfigured, .unknown,
    ]
}
