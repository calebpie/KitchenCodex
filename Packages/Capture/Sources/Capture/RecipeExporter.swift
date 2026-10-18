import Foundation
import Units

/// A recipe as it is shared: what the app's current version says, in display order. The app fills
/// it from RecipeModel; Capture stays free of SwiftData.
public struct ExportRecipe: Sendable, Equatable {
    public struct Ingredient: Sendable, Equatable {
        public var group: String?
        /// The amount as written; nil when the line has none. "To taste" has a unit and no amount.
        public var quantity: Quantity?
        public var item: String
        public var preparation: String?
        /// "about 3 oranges", "plus more for the pan": printed after the preparation as its form says.
        public var note: String?
        /// A clause note follows a comma, a parenthetical keeps its parentheses (`NoteForm.suffix`).
        public var noteForm: NoteForm?
        public var isOptional: Bool

        public init(group: String? = nil, quantity: Quantity? = nil, item: String, preparation: String? = nil, note: String? = nil, noteForm: NoteForm? = nil, isOptional: Bool = false) {
            self.group = group
            self.quantity = quantity
            self.item = item
            self.preparation = preparation
            self.note = note
            self.noteForm = noteForm
            self.isOptional = isOptional
        }

        /// "1½ cups", or nil for a line without an amount (and for "to taste", which reads after the item).
        public var amount: String? {
            guard let quantity, quantity.unit != .toTaste else { return nil }
            return quantity.formatted()
        }

        /// The item with its preparation, note and flags: "unsalted butter, softened", "flaky salt,
        /// to taste", "orange juice (about 3 oranges)", "all-purpose flour, plus extra (for kneading)".
        public var description: String {
            var text = item
            if let preparation, !preparation.isEmpty { text += ", \(preparation)" }
            if quantity?.unit == .toTaste { text += ", to taste" }
            if let note, !note.isEmpty { text += NoteForm.suffix(for: note, form: noteForm) }
            if isOptional { text += " (optional)" }
            return text
        }

        /// The whole line as a cook reads it.
        public var line: String {
            amount.map { "\($0) \(description)" } ?? description
        }
    }

    public var title: String
    /// "Serious Eats · J. Kenji López-Alt", "Six Seasons, p. 112", "Added by hand".
    public var sourceLine: String?
    public var sourceURL: URL?
    /// "Serves 4", "Makes 30 cookies".
    public var yield: String?
    public var prepMinutes: Int?
    public var cookMinutes: Int?
    public var totalMinutes: Int?
    public var ingredients: [Ingredient]
    public var steps: [String]
    public var notes: String?

    public init(
        title: String,
        sourceLine: String? = nil,
        sourceURL: URL? = nil,
        yield: String? = nil,
        prepMinutes: Int? = nil,
        cookMinutes: Int? = nil,
        totalMinutes: Int? = nil,
        ingredients: [Ingredient] = [],
        steps: [String] = [],
        notes: String? = nil
    ) {
        self.title = title
        self.sourceLine = sourceLine
        self.sourceURL = sourceURL
        self.yield = yield
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.totalMinutes = totalMinutes
        self.ingredients = ingredients
        self.steps = steps
        self.notes = notes
    }

    /// Runs of ingredients under the same heading, in order.
    public var ingredientGroups: [(name: String?, ingredients: [Ingredient])] {
        var groups: [(name: String?, ingredients: [Ingredient])] = []
        for ingredient in ingredients {
            let name = ingredient.group.flatMap { $0.isEmpty ? nil : $0 }
            if let last = groups.last, last.name == name {
                groups[groups.count - 1].ingredients.append(ingredient)
            } else {
                groups.append((name, [ingredient]))
            }
        }
        return groups
    }

    /// "Prep 15 min", "Cook 1 hr 10 min", "Total 1 hr 25 min", for the times that are given.
    public var timeParts: [String] {
        [("Prep", prepMinutes), ("Cook", cookMinutes), ("Total", totalMinutes)].compactMap { label, minutes in
            minutes.flatMap { $0 > 0 ? "\(label) \(RecipeExporter.minutesText($0))" : nil }
        }
    }

    /// Yield and times on one line: "Serves 4 · Prep 15 min · Cook 1 hr 10 min".
    public var metaLine: String? {
        let parts = [yield].compactMap { $0?.isEmpty == false ? $0 : nil } + timeParts
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Markdown and plain text for sharing a recipe (Phase 1 exports): title, source line, yield and
/// times, ingredients under their group headings with amounts from Units' `formatted()`, numbered
/// steps, notes. Deterministic, so the output is snapshot-tested.
public enum RecipeExporter {
    public static func markdown(_ recipe: ExportRecipe) -> String {
        var blocks: [String] = ["# \(escape(recipe.title))"]

        var source: [String] = []
        if let line = recipe.sourceLine, !line.isEmpty { source.append("*\(escape(line))*") }
        if let url = recipe.sourceURL { source.append("<\(url.absoluteString)>") }
        if !source.isEmpty { blocks.append(source.joined(separator: "  \n")) }
        if let meta = recipe.metaLine { blocks.append(escape(meta)) }

        if !recipe.ingredients.isEmpty {
            blocks.append("## Ingredients")
            for group in recipe.ingredientGroups {
                var lines: [String] = []
                if let name = group.name { lines.append("### \(escape(name))\n") }
                for ingredient in group.ingredients {
                    if let amount = ingredient.amount {
                        lines.append("- **\(escape(amount))** \(escape(ingredient.description))")
                    } else {
                        lines.append("- \(escape(ingredient.description))")
                    }
                }
                blocks.append(lines.joined(separator: "\n"))
            }
        }

        if !recipe.steps.isEmpty {
            blocks.append("## Steps")
            blocks.append(recipe.steps.enumerated().map { "\($0.offset + 1). \(escape(oneParagraph($0.element)))" }.joined(separator: "\n"))
        }

        if let notes = recipe.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            blocks.append("## Notes")
            blocks.append(paragraphs(notes).map(escape).joined(separator: "\n\n"))
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    public static func plainText(_ recipe: ExportRecipe) -> String {
        var blocks: [String] = []
        var header = [recipe.title]
        if let line = recipe.sourceLine, !line.isEmpty { header.append(line) }
        if let url = recipe.sourceURL { header.append(url.absoluteString) }
        if let meta = recipe.metaLine { header.append(meta) }
        blocks.append(header.joined(separator: "\n"))

        if !recipe.ingredients.isEmpty {
            var lines = ["INGREDIENTS"]
            for (index, group) in recipe.ingredientGroups.enumerated() {
                if let name = group.name {
                    if index > 0 { lines.append("") }
                    lines.append(name)
                }
                lines += group.ingredients.map { "- \($0.line)" }
            }
            blocks.append(lines.joined(separator: "\n"))
        }

        if !recipe.steps.isEmpty {
            blocks.append((["STEPS"] + recipe.steps.enumerated().map { "\($0.offset + 1). \(oneParagraph($0.element))" }).joined(separator: "\n"))
        }

        if let notes = recipe.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            blocks.append("NOTES\n" + paragraphs(notes).joined(separator: "\n\n"))
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// A file name for the recipe: its title without characters file systems refuse.
    public static func fileName(for title: String, extension fileExtension: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cleaned.isEmpty ? "Recipe" : String(cleaned.prefix(80))).\(fileExtension)"
    }

    /// "45 min", "1 hr", "1 hr 10 min", "1 day 2 hr".
    public static func minutesText(_ minutes: Int) -> String {
        let days = minutes / 1_440
        let hours = minutes % 1_440 / 60
        let rest = minutes % 60
        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
        if hours > 0 { parts.append("\(hours) hr") }
        if rest > 0, days == 0 { parts.append("\(rest) min") }
        return parts.isEmpty ? "0 min" : parts.joined(separator: " ")
    }

    // MARK: - Helpers

    /// A step typed across several lines reads as one paragraph in a numbered list.
    private static func oneParagraph(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func paragraphs(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { oneParagraph($0) }
            .filter { !$0.isEmpty }
    }

    /// Escapes what Markdown would read as emphasis or code, so "sh*t’s" and "x_y" print as written.
    static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\*_`[]".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
