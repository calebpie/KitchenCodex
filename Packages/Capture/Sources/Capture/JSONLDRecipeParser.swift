import Foundation

public enum JSONLDParseError: Error, Equatable {
    case notJSON
    case noRecipeFound
}

/// Parses schema.org `Recipe` JSON-LD, the instant path for web imports (Flow A).
///
/// Finds Recipe nodes anywhere in the document (bare, in an array, in `@graph`, or nested under
/// `mainEntity` and the like), resolves `@id` references for authors and images, and tolerates the
/// string-or-array-or-object shapes sites use for every field. Text is cleaned of markup and
/// entities; ingredients are split into lines with group headings pulled out, and instructions
/// (plain text, HTML, `HowToStep`, `HowToSection`) go through `StepSplitter`.
public enum JSONLDRecipeParser {
    /// The first Recipe in the document.
    public static func parse(_ data: Data, sourceURL: URL? = nil) throws -> ImportedRecipe {
        guard let first = try parseAll(data, sourceURL: sourceURL).first else { throw JSONLDParseError.noRecipeFound }
        return first
    }

    /// Every Recipe in the document, in document order.
    public static func parseAll(_ data: Data, sourceURL: URL? = nil) throws -> [ImportedRecipe] {
        guard let json = decode(data) else { throw JSONLDParseError.notJSON }
        var index: [String: [String: Any]] = [:]
        collectIdentifiedNodes(in: json, into: &index)
        var nodes: [[String: Any]] = []
        collectRecipes(in: json, into: &nodes, depth: 0)
        let recipes = nodes.map { recipe(from: $0, index: index, sourceURL: sourceURL) }
        if recipes.isEmpty { throw JSONLDParseError.noRecipeFound }
        return recipes
    }

    // MARK: - Decoding

    private static func decode(_ data: Data) -> Any? {
        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]), json is [String: Any] || json is [Any] {
            return json
        }
        // Repair what pages get wrong: comment or CDATA wrappers, raw line breaks inside strings,
        // trailing commas (JSON5 accepts those).
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for wrapper in ["<!--", "-->", "//<![CDATA[", "//]]>", "<![CDATA[", "]]>"] {
            text = text.replacingOccurrences(of: wrapper, with: "")
        }
        text = text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let repaired = Data(text.utf8)
        if let json = try? JSONSerialization.jsonObject(with: repaired, options: [.fragmentsAllowed]), json is [String: Any] || json is [Any] {
            return json
        }
        if let json = try? JSONSerialization.jsonObject(with: repaired, options: [.json5Allowed, .fragmentsAllowed]), json is [String: Any] || json is [Any] {
            return json
        }
        return nil
    }

    // MARK: - Locating nodes

    private static func collectRecipes(in json: Any, into nodes: inout [[String: Any]], depth: Int) {
        guard depth < 12 else { return }
        if let object = json as? [String: Any] {
            if isRecipe(object) {
                nodes.append(object)
                return
            }
            // Recipes hide under @graph, mainEntity, mainEntityOfPage, hasPart, itemListElement…
            for key in object.keys.sorted() where key != "@context" {
                collectRecipes(in: object[key]!, into: &nodes, depth: depth + 1)
            }
        } else if let array = json as? [Any] {
            for element in array {
                collectRecipes(in: element, into: &nodes, depth: depth + 1)
            }
        }
    }

    private static func collectIdentifiedNodes(in json: Any, into index: inout [String: [String: Any]]) {
        if let object = json as? [String: Any] {
            if let id = object["@id"] as? String, object.count > 1, index[id] == nil {
                index[id] = object
            }
            for value in object.values { collectIdentifiedNodes(in: value, into: &index) }
        } else if let array = json as? [Any] {
            for element in array { collectIdentifiedNodes(in: element, into: &index) }
        }
    }

    private static func isRecipe(_ object: [String: Any]) -> Bool {
        strings(object["@type"]).contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame }
    }

    // MARK: - Building the recipe

    private static func recipe(from node: [String: Any], index: [String: [String: Any]], sourceURL: URL?) -> ImportedRecipe {
        let base = sourceURL ?? string(node["url"]).flatMap { URL(string: $0) }
        let ingredients = ImportText.ingredientList(strings(node["recipeIngredient"] ?? node["ingredients"]))
        return ImportedRecipe(
            title: ImportText.inline(string(node["name"]) ?? string(node["headline"]) ?? ""),
            ingredients: ingredients.lines,
            steps: instructions(node["recipeInstructions"], index: index),
            yield: YieldText.best(strings(node["recipeYield"] ?? node["yield"])),
            author: author(node["author"] ?? node["creator"], index: index),
            siteName: name(of: node["publisher"], index: index),
            sourceURL: sourceURL ?? ImportText.url(string(node["url"]), relativeTo: nil),
            imageURL: image(node["image"] ?? node["thumbnailUrl"], index: index, base: base),
            prepTime: duration(node["prepTime"]),
            cookTime: duration(node["cookTime"]),
            totalTime: duration(node["totalTime"]),
            category: strings(node["recipeCategory"]).first.map(ImportText.inline),
            cuisine: strings(node["recipeCuisine"]).first.map(ImportText.inline),
            ingredientGroups: ingredients.groups,
            method: .jsonLD,
            confidence: 0.95
        )
    }

    // MARK: - Field coercion

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let n as NSNumber:
            return n.stringValue
        default:
            return nil
        }
    }

    private static func strings(_ value: Any?) -> [String] {
        switch value {
        case let array as [Any]: array.compactMap { string($0) }
        default: string(value).map { [$0] } ?? []
        }
    }

    private static func resolve(_ value: Any?, index: [String: [String: Any]]) -> Any? {
        if let object = value as? [String: Any], let id = object["@id"] as? String, object.count == 1 {
            return index[id] ?? object
        }
        return value
    }

    private static func instructions(_ value: Any?, index: [String: [String: Any]]) -> [String] {
        switch resolve(value, index: index) {
        case let text as String:
            return ImportText.steps(from: text)
        case let array as [Any]:
            return array.flatMap { instructions($0, index: index) }
        case let object as [String: Any]:
            // HowToSection and ItemList hold steps; HowToStep has text (or only a name).
            if let elements = object["itemListElement"] {
                return instructions(elements, index: index)
            }
            if let text = string(object["text"]) ?? string(object["description"]) ?? string(object["name"]) {
                return ImportText.steps(from: text)
            }
            return []
        default:
            return []
        }
    }

    private static func name(of value: Any?, index: [String: [String: Any]]) -> String? {
        switch resolve(value, index: index) {
        case let text as String:
            let cleaned = ImportText.inline(text)
            return cleaned.isEmpty ? nil : cleaned
        case let object as [String: Any]:
            return string(object["name"]).map(ImportText.inline)
        case let array as [Any]:
            return array.lazy.compactMap { name(of: $0, index: index) }.first
        default:
            return nil
        }
    }

    /// One author, or several joined as "A and B" / "A, B and C".
    private static func author(_ value: Any?, index: [String: [String: Any]]) -> String? {
        let names: [String]
        if let array = resolve(value, index: index) as? [Any] {
            names = array.compactMap { name(of: $0, index: index) }
        } else {
            names = name(of: value, index: index).map { [$0] } ?? []
        }
        // Some sites put a profile URL where the name belongs.
        let people = names.filter { !$0.hasPrefix("http") }
        var unique: [String] = []
        for person in people where !unique.contains(person) { unique.append(person) }
        switch unique.count {
        case 0: return nil
        case 1: return unique[0]
        default: return unique.dropLast().joined(separator: ", ") + " and " + unique.last!
        }
    }

    private static func image(_ value: Any?, index: [String: [String: Any]], base: URL?) -> URL? {
        switch resolve(value, index: index) {
        case let text as String:
            return ImportText.url(text, relativeTo: base)
        case let object as [String: Any]:
            return ImportText.url(string(object["url"]) ?? string(object["contentUrl"]), relativeTo: base)
        case let array as [Any]:
            return array.lazy.compactMap { image($0, index: index, base: base) }.first
        default:
            return nil
        }
    }

    private static func duration(_ value: Any?) -> Duration? {
        guard let text = string(value) else { return nil }
        let parsed = ISO8601Duration.parse(text) ?? TextDuration.parse(text)
        // "PT0S" and friends mean "not given".
        return parsed == .zero ? nil : parsed
    }
}
