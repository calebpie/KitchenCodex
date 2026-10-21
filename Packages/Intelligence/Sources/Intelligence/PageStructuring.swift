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

/// A book's contents page as a model reads it: its chapters in order, each with the page it starts
/// on and the recipe titles it lists with theirs. Pages are nil where none is printed.
public struct StructuredContentsDraft: Sendable, Codable, Equatable {
    public struct Entry: Sendable, Codable, Equatable {
        public var title: String
        public var page: Int?

        public init(title: String, page: Int? = nil) {
            self.title = title
            self.page = page
        }
    }

    public struct Section: Sendable, Codable, Equatable {
        /// Empty for the entries before the page's first chapter heading.
        public var title: String
        public var page: Int?
        public var entries: [Entry]

        public init(title: String, page: Int? = nil, entries: [Entry] = []) {
            self.title = title
            self.page = page
            self.entries = entries
        }
    }

    public var sections: [Section]

    public init(sections: [Section]) {
        self.sections = sections
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
    /// A contents or index page's chapters and recipe titles with their page numbers (02 Flow C
    /// step 3), for Capture's contents reading when its deterministic reading finds few entries or
    /// no page numbers. A structurer that can't read contents throws.
    func structureContents(pageText: String) async throws -> StructuredContentsDraft
}

extension PageStructuring {
    public var acceptsImages: Bool { false }

    public func structure(pageText: String, image: CGImage) async throws -> StructuredPageDraft {
        try await structure(pageText: pageText)
    }

    public func structureContents(pageText: String) async throws -> StructuredContentsDraft {
        throw ModelUnavailabilityError(reason: .notConfigured)
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

    public func structureContents(pageText: String) async throws -> StructuredContentsDraft {
        #if canImport(FoundationModels)
        guard isAvailable else {
            if case let .failure(error) = ModelAvailability.onDevice() { throw error }
            throw ModelUnavailabilityError(reason: .unknown)
        }
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.contentsInstructions)
        let text = String(pageText.prefix(characterBudget))
        let response = try await session.respond(
            to: "Recognized text of the contents page, in reading order:\n\n\(text)",
            generating: GeneratedContents.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        func page(_ value: Int) -> Int? { value > 0 && value < 2_000 ? value : nil }
        return StructuredContentsDraft(sections: response.content.sections.map { section in
            StructuredContentsDraft.Section(
                title: clean(section.title),
                page: page(section.page),
                entries: section.entries.map { StructuredContentsDraft.Entry(title: clean($0.title), page: page($0.page)) }
                    .filter { !$0.title.isEmpty }
            )
        })
        #else
        throw ModelUnavailabilityError(reason: .notConfigured)
        #endif
    }

    static let contentsInstructions = """
        You read the contents pages of cookbooks. The text was recognized from a photo, in reading \
        order, and may include running heads, page numbers on their own and parts of the facing \
        page. Return the book's chapters in order, each with the page it starts on, and under each \
        the recipe titles it lists with their page numbers. A title wrapped onto a second line is \
        one title. Copy titles exactly as printed; never invent a title or a page number. Use 0 \
        for a page number that is not printed. Entries before the first chapter heading go in a \
        chapter with an empty title.
        """

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

@Generable(description: "A cookbook's contents page: its chapters in order")
struct GeneratedContents {
    @Guide(description: "Each chapter in the order printed; entries before the first heading in a chapter with an empty title")
    var sections: [GeneratedContentsSection]
}

@Generable(description: "One chapter of a contents page")
struct GeneratedContentsSection {
    @Guide(description: "The chapter's title as printed; empty for entries before the first heading")
    var title: String

    @Guide(description: "The page the chapter starts on, or 0 if none is printed")
    var page: Int

    @Guide(description: "The recipe titles listed under the chapter, in order")
    var entries: [GeneratedContentsEntry]
}

@Generable(description: "One recipe title on a contents page")
struct GeneratedContentsEntry {
    @Guide(description: "The title exactly as printed, a wrapped title joined into one")
    var title: String

    @Guide(description: "The page number printed with it, or 0 if none")
    var page: Int
}
#endif
