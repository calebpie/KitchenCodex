import Foundation

/// A recipe app whose export Recipe Codex reads.
public enum LibraryFormat: String, Sendable, CaseIterable {
    /// `.paprikarecipes`: a ZIP of gzipped JSON files, one per recipe (`.paprikarecipe`).
    case paprika
    /// `.melarecipes`: a ZIP of JSON files, one per recipe; `.melarecipe` is one recipe's JSON.
    case mela

    public var appName: String {
        switch self {
        case .paprika: "Paprika"
        case .mela: "Mela"
        }
    }

    /// The file extensions each app writes, archive first.
    public var fileExtensions: [String] {
        switch self {
        case .paprika: ["paprikarecipes", "paprikarecipe"]
        case .mela: ["melarecipes", "melarecipe"]
        }
    }

    public static var allFileExtensions: [String] { allCases.flatMap(\.fileExtensions) }
}

/// Why one recipe in a library file couldn't be read.
public enum LibraryImportError: Error, Equatable, LocalizedError {
    case unknownFormat
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .unknownFormat: "That file isn't a Paprika or Mela export."
        case let .unreadable(name): "“\(name)” couldn't be read."
        }
    }
}

/// An export from another recipe app, opened lazily: `count` recipes, each read on demand by
/// `recipe(at:)` so a large library can show progress and never holds every photo at once.
public struct LibraryArchive: Sendable {
    public let format: LibraryFormat
    private let items: [Item]
    private let archive: ZipArchive?
    private let single: Data?

    private enum Item: Sendable {
        case entry(ZipArchive.Entry)
        case whole(String)

        var name: String {
            switch self {
            case let .entry(entry): entry.fileName
            case let .whole(name): name
            }
        }
    }

    public var count: Int { items.count }

    /// The file name of each recipe inside, for reporting what couldn't be read.
    public func name(at index: Int) -> String { items[index].name }

    /// Opens `data`, using the file's extension when it names a format and the contents otherwise.
    public init(data: Data, fileName: String) throws {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        let named = LibraryFormat.allCases.first { $0.fileExtensions.contains(fileExtension) }

        if ZipArchive.isZip(data) {
            let zip = try ZipArchive(data: data)
            let files = zip.files
            let format = named ?? Self.sniffFormat(of: files.map(\.fileName))
            guard let format else { throw LibraryImportError.unknownFormat }
            let wanted = files.filter { entry in
                let ext = (entry.fileName as NSString).pathExtension.lowercased()
                return format.fileExtensions.contains(ext) || (format == .mela && ext == "json")
            }
            self.format = format
            archive = zip
            single = nil
            items = wanted.map(Item.entry)
        } else {
            let format: LibraryFormat
            if let named {
                format = named
            } else if Inflate.isGzip(data) {
                format = .paprika
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                format = json["title"] != nil ? .mela : .paprika
            } else {
                throw LibraryImportError.unknownFormat
            }
            self.format = format
            archive = nil
            single = data
            items = [.whole(fileName)]
        }
    }

    private static func sniffFormat(of names: [String]) -> LibraryFormat? {
        for name in names {
            let ext = (name as NSString).pathExtension.lowercased()
            if let format = LibraryFormat.allCases.first(where: { $0.fileExtensions.contains(ext) }) { return format }
        }
        return nil
    }

    /// The recipe at `index`, ready for the same save path as a web import.
    public func recipe(at index: Int) throws -> ImportedRecipe {
        let item = items[index]
        var data: Data
        switch item {
        case let .entry(entry):
            guard let archive else { throw LibraryImportError.unreadable(item.name) }
            data = try archive.contents(of: entry)
        case .whole:
            guard let single else { throw LibraryImportError.unreadable(item.name) }
            data = single
        }
        if Inflate.isGzip(data) {
            guard let inflated = Inflate.gunzip(data) else { throw LibraryImportError.unreadable(item.name) }
            data = inflated
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibraryImportError.unreadable(item.name)
        }
        switch format {
        case .paprika: return PaprikaImporter.recipe(from: json)
        case .mela: return MelaImporter.recipe(from: json)
        }
    }
}

/// Paprika's recipe JSON (one per `.paprikarecipe`, gzipped).
///
/// | Paprika | Recipe Codex |
/// |---|---|
/// | `name` | title |
/// | `ingredients` (lines; "For the sauce:" lines are headings) | ingredients and groups |
/// | `directions` (paragraphs, else lines) | steps |
/// | `notes` | notes |
/// | `description` | headnote |
/// | `servings` | yield (label stripped) |
/// | `prep_time`, `cook_time`, `total_time` ("15 mins", "1 hr 10 mins") | times |
/// | `source`, `source_url` | site name, source URL |
/// | `image_url`, `photo_data` (base64) | cover |
/// | `categories` | tags, each one; and the course, where one names a course |
/// | `on_favorites`, `rating` (0–5) | favorite when on favorites or rated 4 or more |
/// | `created` ("2021-03-14 18:22:05") | added date |
///
/// `difficulty`, `nutritional_info`, extra `photos` and ratings below 4 are not kept (no field for
/// them yet).
public enum PaprikaImporter {
    public static func recipe(from json: [String: Any]) -> ImportedRecipe {
        let ingredients = ImportText.ingredientList([LibraryFields.string(json["ingredients"]) ?? ""])
        var recipe = ImportedRecipe(
            title: LibraryFields.title(json["name"]),
            ingredients: ingredients.lines,
            steps: LibraryFields.steps(json["directions"]),
            yield: LibraryFields.string(json["servings"]).map(YieldText.strippingLabel),
            siteName: LibraryFields.string(json["source"]),
            sourceURL: LibraryFields.url(json["source_url"]),
            imageURL: LibraryFields.url(json["image_url"]),
            prepTime: LibraryFields.duration(json["prep_time"]),
            cookTime: LibraryFields.duration(json["cook_time"]),
            totalTime: LibraryFields.duration(json["total_time"]),
            category: LibraryFields.categories(json["categories"]),
            ingredientGroups: ingredients.groups,
            method: .libraryFile,
            confidence: 0.95
        )
        recipe.notes = LibraryFields.string(json["notes"]).map { [$0] } ?? []
        recipe.headnote = LibraryFields.string(json["description"])
        recipe.categories = LibraryFields.categoryNames(json["categories"])
        recipe.isFavorite = LibraryFields.bool(json["on_favorites"]) || (LibraryFields.int(json["rating"]) ?? 0) >= LibraryFields.favoriteRating
        recipe.imageData = LibraryFields.base64(json["photo_data"])
            ?? (json["photos"] as? [[String: Any]])?.lazy.compactMap { LibraryFields.base64($0["data"]) }.first
        recipe.createdAt = LibraryFields.date(json["created"])
        recipe.importedFrom = LibraryFormat.paprika.appName
        recipe.movingAsidesToNotes()
        return recipe
    }
}

/// Mela's recipe JSON (`.melarecipe`).
///
/// | Mela | Recipe Codex |
/// |---|---|
/// | `title` | title |
/// | `ingredients` (lines; "# Dough" lines are headings) | ingredients and groups |
/// | `instructions` (lines; "# Section" lines dropped) | steps |
/// | `notes` | notes |
/// | `text` | headnote |
/// | `yield` | yield (label stripped) |
/// | `prepTime`, `cookTime`, `totalTime` | times |
/// | `link` (a URL, or a book's name) | source URL, else site name |
/// | `images` (base64, first kept) | cover |
/// | `categories` | tags, each one; and the course, where one names a course |
/// | `favorite` | favorite |
/// | `date` (seconds since 2001, or ISO 8601) | added date |
///
/// `nutrition`, `wantToCook` and further images are not kept. Mela exports no rating.
public enum MelaImporter {
    public static func recipe(from json: [String: Any]) -> ImportedRecipe {
        let ingredientText = (LibraryFields.string(json["ingredients"]) ?? "")
            .components(separatedBy: .newlines)
            .map { line in
                // Mela marks a group with "# Heading"; the shared list reader wants "Heading:".
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("#") else { return line }
                return trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) + ":"
            }
            .joined(separator: "\n")
        let ingredients = ImportText.ingredientList([ingredientText])
        let instructions = (LibraryFields.string(json["instructions"]) ?? "")
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        let link = LibraryFields.string(json["link"])
        let linkURL = LibraryFields.url(link)

        var recipe = ImportedRecipe(
            title: LibraryFields.title(json["title"]),
            ingredients: ingredients.lines,
            steps: LibraryFields.steps(instructions),
            yield: LibraryFields.string(json["yield"]).map(YieldText.strippingLabel),
            siteName: linkURL == nil ? link : nil,
            sourceURL: linkURL,
            prepTime: LibraryFields.duration(json["prepTime"]),
            cookTime: LibraryFields.duration(json["cookTime"]),
            totalTime: LibraryFields.duration(json["totalTime"]),
            category: LibraryFields.categories(json["categories"]),
            ingredientGroups: ingredients.groups,
            method: .libraryFile,
            confidence: 0.95
        )
        recipe.notes = LibraryFields.string(json["notes"]).map { [$0] } ?? []
        recipe.headnote = LibraryFields.string(json["text"])
        recipe.categories = LibraryFields.categoryNames(json["categories"])
        recipe.isFavorite = LibraryFields.bool(json["favorite"])
        recipe.imageData = (json["images"] as? [Any])?.lazy.compactMap { LibraryFields.base64($0) }.first
        recipe.createdAt = LibraryFields.date(json["date"])
        recipe.importedFrom = LibraryFormat.mela.appName
        recipe.movingAsidesToNotes()
        return recipe
    }
}

/// Field coercion shared by the library importers.
enum LibraryFields {
    static func string(_ value: Any?) -> String? {
        let text: String?
        switch value {
        case let s as String: text = s
        case let n as NSNumber: text = n.stringValue
        default: text = nil
        }
        let trimmed = text?.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func title(_ value: Any?) -> String {
        string(value).map(ImportText.inline) ?? "Untitled Recipe"
    }

    /// Steps as the app stored them: paragraphs when separated by blank lines, else one per line.
    static func steps(_ value: Any?) -> [ImportedStep] {
        guard let text = string(value) else { return [] }
        return StepSplitter.steps(from: text).filter { !ImportText.isSectionLabel($0) }.map { ImportedStep(text: $0) }
    }

    static func url(_ value: Any?) -> URL? {
        ImportText.url(string(value), relativeTo: nil)
    }

    static func duration(_ value: Any?) -> Duration? {
        guard let text = string(value) else { return nil }
        if let minutes = Int(text) { return minutes > 0 ? .seconds(minutes * 60) : nil }
        return ISO8601Duration.parse(text) ?? TextDuration.parse(text)
    }

    /// Categories joined with commas, which is how the course matcher reads a page's `recipeCategory`.
    static func categories(_ value: Any?) -> String? {
        let names = categoryNames(value)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// Each category once, as written, in order: strings or `{"name": …}` objects; a repeat that
    /// differs only in case is dropped.
    static func categoryNames(_ value: Any?) -> [String] {
        let names: [String]
        switch value {
        case let array as [Any]: names = array.compactMap { string($0) ?? string(($0 as? [String: Any])?["name"]) }
        default: names = string(value).map { [$0] } ?? []
        }
        var seen: Set<String> = []
        return names.map(ImportText.inline).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// A Paprika rating at or above this makes the recipe a favorite.
    static let favoriteRating = 4

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let b as Bool: b ? 1 : 0
        case let n as NSNumber: n.intValue
        case let s as String: Int(s.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    static func bool(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: b
        case let n as NSNumber: n.intValue != 0
        case let s as String: ["1", "true", "yes"].contains(s.lowercased())
        default: false
        }
    }

    static func base64(_ value: Any?) -> Data? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return Data(base64Encoded: text, options: .ignoreUnknownCharacters)
    }

    static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber, !(value is Bool) {
            let seconds = number.doubleValue
            // Mela writes seconds since 2001; Unix timestamps are much larger for any recent date.
            return seconds > 1_000_000_000 ? Date(timeIntervalSince1970: seconds) : Date(timeIntervalSinceReferenceDate: seconds)
        }
        guard let text = string(value) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: text) { return date }
        return try? Date(text, strategy: .iso8601)
    }
}
