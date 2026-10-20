import CoreGraphics
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A cookbook page's recipe as a model reads it: what Capture's page reading falls back on when its
/// deterministic reading of a scanned page has no title, ingredients or steps (Phase 1 slice 10's
/// rule, applied to pages).
public struct StructuredPageDraft: Sendable, Codable, Equatable {
    public var title: String
    public var yield: String?
    public var headnote: String?
    public var ingredients: [String]
    public var steps: [String]
    /// 0…1, the structurer's own figure.
    public var confidence: Double

    public init(title: String, yield: String? = nil, headnote: String? = nil, ingredients: [String], steps: [String], confidence: Double) {
        self.title = title
        self.yield = yield
        self.headnote = headnote
        self.ingredients = ingredients
        self.steps = steps
        self.confidence = confidence
    }
}

/// Anything that can read a recipe off a cookbook page's recognized text, and, when it can see, off
/// the page's photo as well.
public protocol PageStructuring: Sendable {
    /// Whether `structure` can run now. A model-backed structurer answers false when the model is
    /// unavailable, so callers keep their deterministic reading.
    var isAvailable: Bool { get }
    /// Whether the structurer takes the page's image too (`structure(pageText:image:)`).
    var acceptsImages: Bool { get }
    func structure(pageText: String) async throws -> StructuredPageDraft
    func structure(pageText: String, image: CGImage) async throws -> StructuredPageDraft
}

extension PageStructuring {
    public var acceptsImages: Bool { false }

    public func structure(pageText: String, image: CGImage) async throws -> StructuredPageDraft {
        try await structure(pageText: pageText)
    }
}

/// Reads a cookbook page with Apple's on-device model: the recognized text in reading order, and,
/// on a model that takes images (`LanguageModelCapabilities.vision`, iOS 27 and macOS 27), the
/// photo itself as a third pass. The model is told to copy lines as printed and to keep each
/// printed paragraph of the method as one step, never splitting or merging them.
public struct OnDevicePageStructurer: PageStructuring {
    /// A model reading is always worth a look, as on the web (`OnDeviceRecipeStructurer`).
    public static let reportedConfidence = 0.6

    public init() {}

    public var isAvailable: Bool {
        if case .success = ModelAvailability.onDevice() { return true }
        return false
    }

    public var acceptsImages: Bool {
        #if canImport(FoundationModels)
        guard isAvailable else { return false }
        return SystemLanguageModel.default.capabilities.contains(.vision)
        #else
        return false
        #endif
    }

    public func structure(pageText: String) async throws -> StructuredPageDraft {
        #if canImport(FoundationModels)
        let session = try session()
        let text = String(pageText.prefix(characterBudget))
        let response = try await session.respond(
            to: "Recognized text of the page, in reading order:\n\n\(text)",
            generating: GeneratedPage.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return Self.draft(response.content)
        #else
        throw ModelUnavailabilityError(reason: .notConfigured)
        #endif
    }

    public func structure(pageText: String, image: CGImage) async throws -> StructuredPageDraft {
        #if canImport(FoundationModels)
        guard acceptsImages else { return try await structure(pageText: pageText) }
        let session = try session()
        let text = String(pageText.prefix(characterBudget / 2))
        let response = try await session.respond(generating: GeneratedPage.self, options: GenerationOptions(samplingMode: .greedy)) {
            "A photo of the page, and the text recognized on it in reading order. Read the recipe from the photo; use the text for spelling.\n\n\(text)"
            Attachment(image)
        }
        return Self.draft(response.content)
        #else
        throw ModelUnavailabilityError(reason: .notConfigured)
        #endif
    }

    #if canImport(FoundationModels)
    private var characterBudget: Int {
        max(2_000, Int(Double(SystemLanguageModel.default.contextSize) * 1.4))
    }

    private func session() throws -> LanguageModelSession {
        guard isAvailable else {
            if case let .failure(error) = ModelAvailability.onDevice() { throw error }
            throw ModelUnavailabilityError(reason: .unknown)
        }
        return LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.instructions)
    }

    private static func draft(_ page: GeneratedPage) -> StructuredPageDraft {
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let yield = clean(page.yield)
        let headnote = clean(page.headnote)
        return StructuredPageDraft(
            title: clean(page.title),
            yield: yield.isEmpty ? nil : yield,
            headnote: headnote.isEmpty ? nil : headnote,
            ingredients: page.ingredients.map(clean).filter { !$0.isEmpty },
            steps: page.steps.map(clean).filter { !$0.isEmpty },
            confidence: reportedConfidence
        )
    }
    #endif

    static let instructions = """
        You read pages photographed from cookbooks. The text was recognized from the photo and may \
        include running heads, page numbers, captions and parts of the facing page. Find the recipe \
        and return its title, its yield, its introduction, every ingredient line and every step of \
        the method, in the page's order. Copy ingredient lines exactly as printed, with amounts and \
        units. Each printed paragraph of the method is one step: never split a paragraph into \
        several steps or join paragraphs. Copy the page's words; do not summarize, invent or add \
        anything that is not on the page. Leave a field empty when the page does not have it.
        """
}

#if canImport(FoundationModels)
@Generable(description: "A recipe read from a cookbook page")
struct GeneratedPage {
    @Guide(description: "The recipe's title as printed")
    var title: String

    @Guide(description: "The yield as printed, such as Serves 4 or Makes 2 cups; empty if none")
    var yield: String

    @Guide(description: "The introduction printed before the ingredients or method; empty if none")
    var headnote: String

    @Guide(description: "Every ingredient line in order, exactly as printed, with its amount and unit")
    var ingredients: [String]

    @Guide(description: "Every paragraph of the method in order, one step per printed paragraph, in the page's words")
    var steps: [String]
}
#endif
