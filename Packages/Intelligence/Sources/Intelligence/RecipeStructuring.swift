import Foundation

/// The model-agnostic shape every recipe structurer produces. Capture turns this into
/// RecipeModel objects; Phase 2 replaces plain strings with structured ingredients and steps.
public struct StructuredRecipeDraft: Sendable, Codable, Equatable {
    public var title: String
    public var ingredients: [String]
    public var steps: [String]
    /// 0...1. Deterministic parsers report how sure they are so the review queue can prioritize.
    public var confidence: Double

    public init(title: String, ingredients: [String], steps: [String], confidence: Double) {
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.confidence = confidence
    }
}

/// Anything that can turn free text (OCR output, pasted text, a web page's visible text) into a
/// recipe draft.
public protocol RecipeStructuring: Sendable {
    /// Whether `structure` can run right now. A model-backed structurer answers false when the model
    /// is unavailable, so callers keep their deterministic result instead of waiting on an error.
    var isAvailable: Bool { get }
    func structure(_ text: String) async throws -> StructuredRecipeDraft
}

extension RecipeStructuring {
    public var isAvailable: Bool { true }
}

/// The non-model path. Splits on "Ingredients" / "Method|Directions|Instructions|Steps" headings.
/// Good enough for well-formatted text; the on-device model takes over when confidence is low.
public struct DeterministicRecipeStructurer: RecipeStructuring {
    public init() {}

    public func structure(_ text: String) async throws -> StructuredRecipeDraft {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var title = lines.first ?? ""
        var ingredients: [String] = []
        var steps: [String] = []
        var section: Section = .preamble

        for line in lines {
            if let heading = Section(heading: line) {
                section = heading
                continue
            }
            switch section {
            case .preamble:
                if title.isEmpty { title = line }
            case .ingredients:
                ingredients.append(line)
            case .steps:
                steps.append(Self.stripStepNumber(line))
            }
        }

        let foundBoth = !ingredients.isEmpty && !steps.isEmpty
        return StructuredRecipeDraft(
            title: title,
            ingredients: ingredients,
            steps: steps,
            confidence: foundBoth ? 0.8 : 0.3
        )
    }

    private enum Section {
        case preamble, ingredients, steps

        init?(heading line: String) {
            let normalized = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            switch normalized {
            case "ingredients": self = .ingredients
            case "method", "directions", "instructions", "steps", "preparation": self = .steps
            default: return nil
            }
        }
    }

    private static func stripStepNumber(_ line: String) -> String {
        guard let range = line.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) else { return line }
        return String(line[range.upperBound...])
    }
}
