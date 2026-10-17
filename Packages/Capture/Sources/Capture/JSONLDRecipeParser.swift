import Foundation

public enum JSONLDParseError: Error, Equatable {
    case notJSON
    case noRecipeFound
}

/// Parses schema.org `Recipe` JSON-LD, the instant path for web imports (Flow A).
/// Handles a bare object, an array, and `@graph`; tolerates string-or-array fields.
public enum JSONLDRecipeParser {
    public static func parse(_ data: Data, sourceURL: URL? = nil) throws -> ImportedRecipe {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw JSONLDParseError.notJSON }
        guard let recipe = findRecipe(in: json) else { throw JSONLDParseError.noRecipeFound }

        return ImportedRecipe(
            title: string(recipe["name"]) ?? "",
            ingredients: strings(recipe["recipeIngredient"]),
            steps: instructions(recipe["recipeInstructions"]),
            yield: strings(recipe["recipeYield"]).first,
            author: author(recipe["author"]),
            sourceURL: sourceURL ?? string(recipe["url"]).flatMap(URL.init(string:)),
            imageURL: image(recipe["image"]),
            totalTime: string(recipe["totalTime"]).flatMap(ISO8601Duration.parse)
        )
    }

    // MARK: - Locating the Recipe node

    private static func findRecipe(in json: Any) -> [String: Any]? {
        if let object = json as? [String: Any] {
            if isRecipe(object) { return object }
            if let graph = object["@graph"] as? [Any] { return findRecipe(in: graph) }
            return nil
        }
        if let array = json as? [Any] {
            for element in array {
                if let found = findRecipe(in: element) { return found }
            }
        }
        return nil
    }

    private static func isRecipe(_ object: [String: Any]) -> Bool {
        strings(object["@type"]).contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame }
    }

    // MARK: - Field coercion

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: s.trimmingCharacters(in: .whitespacesAndNewlines)
        case let n as NSNumber: n.stringValue
        default: nil
        }
    }

    private static func strings(_ value: Any?) -> [String] {
        switch value {
        case let s as String: [s.trimmingCharacters(in: .whitespacesAndNewlines)]
        case let array as [Any]: array.compactMap { string($0) }
        default: []
        }
    }

    private static func instructions(_ value: Any?) -> [String] {
        switch value {
        case let s as String:
            s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case let array as [Any]:
            array.flatMap { element -> [String] in
                if let text = string(element) { return [text] }
                guard let object = element as? [String: Any] else { return [] }
                if let section = object["itemListElement"] { return instructions(section) }
                return string(object["text"]).map { [$0] } ?? []
            }
        case let object as [String: Any]:
            instructions(object["itemListElement"])
        default:
            []
        }
    }

    private static func author(_ value: Any?) -> String? {
        if let text = string(value) { return text }
        if let object = value as? [String: Any] { return string(object["name"]) }
        if let array = value as? [Any] { return array.compactMap(author).first }
        return nil
    }

    private static func image(_ value: Any?) -> URL? {
        if let text = string(value) { return URL(string: text) }
        if let object = value as? [String: Any] { return string(object["url"]).flatMap(URL.init(string:)) }
        if let array = value as? [Any] { return array.compactMap(image).first }
        return nil
    }
}

/// Just enough ISO 8601 duration parsing for schema.org times like "PT1H30M".
enum ISO8601Duration {
    static func parse(_ text: String) -> Duration? {
        guard text.hasPrefix("P") else { return nil }
        var seconds = 0
        var number = ""
        var inTime = false
        for character in text.dropFirst() {
            switch character {
            case "T": inTime = true
            case "0"..."9": number.append(character)
            case "D": seconds += (Int(number) ?? 0) * 86_400; number = ""
            case "H": seconds += (Int(number) ?? 0) * 3_600; number = ""
            case "M": seconds += (Int(number) ?? 0) * (inTime ? 60 : 2_592_000); number = ""
            case "S": seconds += Int(number) ?? 0; number = ""
            default: return nil
            }
        }
        return .seconds(seconds)
    }
}
