import Foundation
import Intelligence

/// Why an import from the web failed, worded for the cook.
public enum WebImportError: Error, Equatable, LocalizedError {
    case invalidURL
    case network(String)
    case httpStatus(Int)
    case notAWebPage
    case noRecipeFound

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "That doesn't look like a web address."
        case let .network(message):
            "Couldn't reach the page. \(message)"
        case let .httpStatus(code) where code == 401 || code == 403:
            "The site wouldn't let Kitchen Codex read the page (error \(code))."
        case let .httpStatus(code) where code == 404:
            "The page wasn't found (error 404)."
        case let .httpStatus(code):
            "The site answered with error \(code)."
        case .notAWebPage:
            "That link isn't a web page."
        case .noRecipeFound:
            "No recipe was found on this page."
        }
    }
}

/// What the deterministic importer read from a page, plus what a model would need to try again.
public struct WebPageExtraction: Sendable {
    /// The recipe, or nil when no path found one.
    public var recipe: ImportedRecipe?
    /// The page's title for the recipe (an `<h1>` matched against `<title>`, cleaned of the site name).
    public var pageTitle: String
    public var siteName: String?
    public var author: String?
    public var imageURL: URL?
    public var sourceURL: URL?
    /// Visible text around the recipe (or the start of the page's text), capped for the on-device model.
    public var recipeText: String
    /// Whether `recipeText` shows ingredient lines: amounts with an item (`IngredientParser`), or a
    /// list under an "Ingredients" heading. Without them the model has nothing to copy and invents
    /// a recipe, so it is not asked (`wantsModel`).
    public var hasIngredientLines: Bool
    /// Whether the page-text reading found the page's own headings: its ingredients under an
    /// "Ingredients" heading and its steps under a heading or numbered. False when the reading had
    /// to guess either, or when there was no page-text reading.
    public var readingFoundHeadings = false
    /// The article on a page that carries Article markup and no recipe (`WebReferenceReader`),
    /// for Save as Reference; nil when a recipe was found or the page is no article.
    public var article: ImportedReference?
}

/// Imports a recipe from a web page's HTML (Flow A).
///
/// Deterministic first, model second (04 §1): schema.org JSON-LD, then schema.org microdata, then a
/// reading of the visible text (`PageTextReader`). Each result records its `method` and a
/// `confidence`; JSON-LD is 0.95, microdata 0.85, the page-text reading at most 0.5, below
/// `ImportedRecipe.reviewThreshold`, so it is flagged for review. The model is asked (`refine`) only
/// when that reading lacks a title, ingredients or steps, or is a page-text reading that had to
/// guess where the ingredients or steps are (no headings), and only when the page text shows
/// ingredient lines and a structurer is available (`wantsModel`). Its result is labelled `.model`
/// and still flagged for review. The on-device model takes 10 to 16 seconds a page, so a complete
/// reading is never held back for it (02 Flow A: 2 to 6 seconds).
public struct WebRecipeImporter: Sendable {
    public var structurer: (any RecipeStructuring)?

    public init(structurer: (any RecipeStructuring)? = nil) {
        self.structurer = structurer
    }

    /// Characters of page text handed to the model; the on-device context also has to fit the answer.
    public static let modelTextLimit = 6_000

    /// The model's reading replaces a page-text reading only when it keeps at least this share of
    /// the ingredient lines the page reading found.
    public static let modelKeepsShare = 0.8

    // MARK: - Deterministic

    /// The deterministic paths only. Never touches a model or the network.
    public static func extract(html: String, url: URL?) -> WebPageExtraction {
        let page = HTMLPage(html: html)
        let metadata = PageMetadata(page: page, url: url)
        let reader = PageTextReader(page: page, base: metadata.sourceURL)
        let reading = reader.read()

        let modelInput = modelInput(reader: reader, reading: reading, title: metadata.title)
        var extraction = WebPageExtraction(
            recipe: nil,
            pageTitle: metadata.title,
            siteName: metadata.siteName,
            author: metadata.author,
            imageURL: metadata.imageURL,
            sourceURL: metadata.sourceURL,
            recipeText: modelInput.text,
            hasIngredientLines: reading != nil || showsIngredientLines(modelInput.lines)
        )

        var partial: ImportedRecipe?

        // 1. JSON-LD.
        let structured = page.jsonLDBlocks.flatMap { block in
            (try? JSONLDRecipeParser.parseAll(Data(block.utf8), sourceURL: metadata.sourceURL)) ?? []
        }
        if var recipe = choose(structured, pageTitle: metadata.documentTitle) {
            reconcile(&recipe, with: reading)
            borrowHeadings(&recipe, from: reader)
            if extraction.siteName == nil { extraction.siteName = recipe.siteName }
            finish(&recipe, metadata: metadata, extraction: extraction)
            if recipe.ingredients.count >= 2, !recipe.steps.isEmpty {
                extraction.recipe = recipe
                return extraction
            }
            partial = recipe
        }

        // 2. Microdata.
        if var recipe = MicrodataRecipe.read(page.microdata, base: metadata.sourceURL) {
            reconcile(&recipe, with: reading)
            borrowHeadings(&recipe, from: reader)
            finish(&recipe, metadata: metadata, extraction: extraction)
            if recipe.ingredients.count >= 2, !recipe.steps.isEmpty {
                extraction.recipe = recipe
                return extraction
            }
            partial = partial ?? recipe
        }

        // 3. The page's visible text.
        if let reading {
            extraction.readingFoundHeadings = reading.foundIngredientHeading && reading.foundStepsStructure
            let ingredients = ImportText.ingredientList(reading.ingredients)
            var recipe = partial ?? ImportedRecipe(title: metadata.title)
            if recipe.ingredients.count < ingredients.lines.count {
                recipe.ingredients = ingredients.lines
                recipe.ingredientGroups = ingredients.groups.merging(reading.groups) { first, _ in first }
            }
            if recipe.steps.isEmpty { recipe.steps = reading.importedSteps.map { ImportedStep(text: ImportText.dualMeasures($0.text), imageURL: $0.imageURL) } }
            if recipe.yield == nil { recipe.yield = metadata.yield(near: reading.span, in: reader.lines).map(YieldText.strippingLabel) }
            let times = metadata.times(in: reader.lines)
            recipe.prepTime = recipe.prepTime ?? times.prep
            recipe.cookTime = recipe.cookTime ?? times.cook
            recipe.totalTime = recipe.totalTime ?? times.total
            recipe.method = .pageText
            var confidence = 0.3
            if reading.foundIngredientHeading { confidence += 0.1 }
            if reading.foundStepsStructure, !reading.steps.isEmpty { confidence += 0.1 }
            recipe.confidence = recipe.steps.isEmpty ? 0.2 : confidence
            finish(&recipe, metadata: metadata, extraction: extraction)
            extraction.recipe = recipe
            return extraction
        }

        if var recipe = partial, !recipe.ingredients.isEmpty || !recipe.steps.isEmpty {
            recipe.confidence = 0.4
            extraction.recipe = recipe
        }
        if extraction.recipe == nil {
            extraction.article = WebReferenceReader.read(page: page, metadata: metadata)
        }
        return extraction
    }

    /// The deterministic import, throwing when nothing was found.
    public static func parse(html: String, url: URL?) throws(WebImportError) -> ImportedRecipe {
        guard let recipe = extract(html: html, url: url).recipe else { throw .noRecipeFound }
        return recipe
    }

    // MARK: - With the model

    /// Whether a reading can be shown as it is: it has a title, at least two ingredients and a step.
    public static func isComplete(_ recipe: ImportedRecipe) -> Bool {
        !recipe.title.isEmpty && recipe.ingredients.count >= 2 && !recipe.steps.isEmpty
    }

    /// Whether the model should take a pass at this page: the deterministic reading is missing or
    /// incomplete, or it is a page-text reading that found no headings to go by, and the page text
    /// shows ingredient lines for the model to copy. A complete reading from structured data, or
    /// from a page whose ingredients and steps sit under their headings, stands on its own, flagged
    /// for review when it came from the page text. A shell or home page with no ingredient lines
    /// yields "no recipe found" rather than a recipe the model made up.
    public static func wantsModel(_ extraction: WebPageExtraction) -> Bool {
        guard !extraction.recipeText.isEmpty, extraction.hasIngredientLines else { return false }
        guard let recipe = extraction.recipe, isComplete(recipe) else { return true }
        return recipe.method == .pageText && !extraction.readingFoundHeadings
    }

    /// Whether `refine` would run: `wantsModel`, and the structurer is available.
    public func canRefine(_ extraction: WebPageExtraction) -> Bool {
        guard let structurer, Self.wantsModel(extraction) else { return false }
        return structurer.isAvailable
    }

    /// Asks the structurer to read the page text. Returns nil when it is unavailable, fails, or does
    /// worse than what was already found, so callers keep the deterministic result.
    public func refine(_ extraction: WebPageExtraction) async -> ImportedRecipe? {
        guard canRefine(extraction), let structurer else { return nil }
        guard let draft = try? await structurer.structure(extraction.recipeText) else { return nil }
        let ingredients = ImportText.ingredientList(draft.ingredients)
        let steps = draft.steps.flatMap(ImportText.steps(from:)).map(ImportText.dualMeasures)
            .map { ImportedStep(text: $0, imageURL: Self.imageURL(forStep: $0, in: extraction.recipe)) }
        guard ingredients.lines.count >= 2, !steps.isEmpty else { return nil }
        if let existing = extraction.recipe,
           Double(ingredients.lines.count) < Double(existing.ingredients.count) * Self.modelKeepsShare {
            // The model dropped lines the page reading found; trust the reading.
            return nil
        }

        var recipe = extraction.recipe ?? ImportedRecipe(title: extraction.pageTitle)
        if recipe.title.isEmpty {
            recipe.title = ImportText.cleanTitle(draft.title, siteName: extraction.siteName)
        }
        // The model rarely keeps group headings; carry the page reading's over by line.
        let groups = ingredients.groups.isEmpty ? Self.carryGroups(from: recipe, to: ingredients.lines) : ingredients.groups
        recipe.ingredients = ingredients.lines
        recipe.ingredientGroups = groups
        recipe.steps = steps
        // The model's steps are its own; the page's sections no longer number them.
        recipe.stepGroups = [:]
        recipe.movingAsidesToNotes()
        recipe.method = .model
        recipe.confidence = min(draft.confidence, 0.6)
        recipe.siteName = recipe.siteName ?? extraction.siteName
        recipe.author = recipe.author ?? extraction.author
        recipe.imageURL = recipe.imageURL ?? extraction.imageURL
        recipe.sourceURL = recipe.sourceURL ?? extraction.sourceURL
        return recipe
    }

    /// Deterministic paths, then the model when they come up short and it is available.
    public func importRecipe(html: String, url: URL?) async throws(WebImportError) -> ImportedRecipe {
        let extraction = Self.extract(html: html, url: url)
        if let refined = await refine(extraction) { return refined }
        guard let recipe = extraction.recipe else { throw .noRecipeFound }
        return recipe
    }

    // MARK: - Helpers

    /// The photo the page reading attached to a step with the same text, so a model reading that
    /// copies a step keeps its photo.
    static func imageURL(forStep text: String, in recipe: ImportedRecipe?) -> URL? {
        let key = ImportText.normalizedForComparison(text)
        return recipe?.steps.first { $0.imageURL != nil && ImportText.normalizedForComparison($0.text) == key }?.imageURL
    }

    /// `recipe`'s group headings re-keyed to where their first lines sit in `lines`.
    static func carryGroups(from recipe: ImportedRecipe, to lines: [String]) -> [Int: String] {
        let keys = lines.map(ImportText.normalizedForComparison)
        var groups: [Int: String] = [:]
        for (index, name) in recipe.ingredientGroups where recipe.ingredients.indices.contains(index) {
            let key = ImportText.normalizedForComparison(recipe.ingredients[index])
            if let position = keys.firstIndex(of: key) { groups[position] = name }
        }
        return groups
    }

    /// Several Recipe nodes (a page with a main recipe and a linked one): the one whose name matches
    /// the page's title, else the first with ingredients.
    static func choose(_ recipes: [ImportedRecipe], pageTitle: String?) -> ImportedRecipe? {
        guard recipes.count > 1, let pageTitle else { return recipes.first }
        let title = ImportText.normalizedForComparison(pageTitle)
        func score(_ recipe: ImportedRecipe) -> Int {
            let name = ImportText.normalizedForComparison(recipe.title)
            guard !name.isEmpty else { return 0 }
            if name == title { return 4 }
            if title.contains(name) { return 3 }
            if name.contains(title) { return 2 }
            return recipe.ingredients.isEmpty ? 0 : 1
        }
        return recipes.enumerated().max { lhs, rhs in
            let (left, right) = (score(lhs.element), score(rhs.element))
            return left == right ? lhs.offset > rhs.offset : left < right
        }?.element
    }

    /// Structured data sometimes lists only part of the ingredients (one group of three) or leaves the
    /// steps out. When the page text holds a clearly longer list containing the structured lines, use
    /// it; fill missing steps from the page.
    static func reconcile(_ recipe: inout ImportedRecipe, with reading: PageTextReader.Reading?) {
        guard let reading else { return }
        let page = ImportText.ingredientList(reading.ingredients)
        let count = recipe.ingredients.count
        if page.lines.count >= count + 3, Double(page.lines.count) >= Double(count) * 1.5 {
            let pageKeys = page.lines.map(ImportText.normalizedForComparison)
            let overlap = recipe.ingredients.filter { line in
                let key = ImportText.normalizedForComparison(line)
                return pageKeys.contains { $0 == key || (key.count > 6 && ($0.contains(key) || key.contains($0))) }
            }.count
            if count == 0 || overlap * 2 >= count {
                recipe.ingredients = page.lines
                recipe.ingredientGroups = page.groups.merging(reading.groups) { first, _ in first }
                recipe.confidence = min(recipe.confidence, 0.85)
            }
        }
        if recipe.steps.isEmpty, !reading.steps.isEmpty {
            recipe.steps = reading.importedSteps
            recipe.confidence = min(recipe.confidence, 0.75)
        }
    }

    private static func finish(_ recipe: inout ImportedRecipe, metadata: PageMetadata, extraction: WebPageExtraction) {
        let siteName = metadata.siteName ?? recipe.siteName
        let cleaned = ImportText.cleanTitle(recipe.title, siteName: siteName, host: metadata.sourceURL?.host())
        recipe.title = cleaned.isEmpty ? metadata.title : cleaned
        recipe.siteName = siteName ?? metadata.hostName
        recipe.author = recipe.author ?? metadata.author
        recipe.imageURL = recipe.imageURL ?? metadata.imageURL
        recipe.sourceURL = metadata.sourceURL ?? recipe.sourceURL
        if recipe.ingredients.count < 2 || recipe.steps.isEmpty {
            recipe.confidence = min(recipe.confidence, 0.5)
        }
        recipe.movingAsidesToNotes()
    }

    /// Structured data with a flat ingredient list on a page that shows the same lines under
    /// headings (Rouxbe's lasagne: "Making the Ragu", "Making the Besciamella"…): the page's headings
    /// become the groups. Applies only when most structured lines (80%) are found on the page in
    /// order, each heading sits just above the line it names (at most three lines up, past an
    /// "Ingredients" label), and at least two groups result.
    static func borrowHeadings(_ recipe: inout ImportedRecipe, from reader: PageTextReader) {
        guard recipe.ingredientGroups.isEmpty, recipe.ingredients.count >= 4 else { return }
        let keys = recipe.ingredients.map(ImportText.normalizedForComparison)
        let title = ImportText.normalizedForComparison(recipe.title)
        var groups: [Int: String] = [:]
        var next = 0
        var matched = 0
        var heading: (index: Int, name: String)?
        for (index, line) in reader.lines.enumerated() where next < keys.count {
            let kind = PageTextReader.kind(of: line)
            if kind == .groupHeading || (line.isHeading && kind == .aside) {
                let name = ImportText.groupName(line.text)
                let key = ImportText.normalizedForComparison(name)
                if !key.isEmpty, key != title, name.count <= 50, name.first?.isNumber == false {
                    heading = (index, name)
                }
                continue
            }
            let key = ImportText.normalizedForComparison(ImportText.ingredientLine(line.text))
            // Lines may be skipped (the page can drop one), but never reordered.
            guard let position = keys[next...].firstIndex(of: key), position - next <= 2 else { continue }
            if let found = heading, index - found.index <= 3 {
                groups[position] = found.name
            }
            heading = nil
            matched += 1
            next = position + 1
        }
        guard Double(matched) >= Double(keys.count) * 0.8, Set(groups.values).count >= 2 else { return }
        recipe.ingredientGroups = groups
    }

    /// Ingredient-like lines among those the model would read: at least two with an amount and a
    /// unit ("1 tablespoon soy sauce"), three with an amount and an item ("3 eggs"; a home page's
    /// "2 Michelin-starred chefs" alone is not enough), or two lines listed under an "Ingredients"
    /// heading. Headings never count, so recipe cards titled "12 Holiday Cookies" don't.
    static func showsIngredientLines(_ lines: [PageLine]) -> Bool {
        var withUnit = 0
        var withAmount = 0
        var heading: Int?
        var listed = 0
        for (index, line) in lines.enumerated() {
            let kind = PageTextReader.kind(of: line)
            if case .section(.ingredients) = kind {
                heading = index
                listed = 0
                continue
            }
            if case .ingredient = kind {
                let parsed = IngredientParser.parse(ImportText.ingredientLine(line.text))
                if parsed.quantity != nil, !parsed.item.isEmpty {
                    withAmount += 1
                    if parsed.unit != nil { withUnit += 1 }
                }
            }
            if let start = heading {
                switch kind {
                case .ingredient, .maybeIngredient:
                    listed += 1
                case .section, .prose:
                    heading = nil
                default:
                    break
                }
                if index - start > 12 { heading = nil }
            }
            if withUnit >= 2 || withAmount >= 3 || listed >= 2 { return true }
        }
        return false
    }

    /// The page text handed to the model, and the lines it was taken from.
    private static func modelInput(reader: PageTextReader, reading: PageTextReader.Reading?, title: String) -> (text: String, lines: [PageLine]) {
        let lines = reader.lines
        guard !lines.isEmpty else { return ("", []) }
        let range: Range<Int>
        if let reading {
            range = max(0, reading.span.lowerBound - 8)..<min(lines.count, reading.span.upperBound + 4)
        } else {
            // From the title heading on; the start of a page is mostly navigation.
            let key = ImportText.normalizedForComparison(title)
            let start = lines.firstIndex { $0.headingLevel != nil && ImportText.normalizedForComparison($0.text) == key } ?? 0
            range = start..<lines.count
        }
        var text = title.isEmpty ? "" : "\(title)\n"
        var used: [PageLine] = []
        for line in lines[range] {
            guard text.count + line.text.count < modelTextLimit else { break }
            text += line.text + "\n"
            used.append(line)
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), used)
    }
}

// MARK: - Page metadata

struct PageMetadata {
    var title: String
    /// `og:title` or `<title>`, for matching against recipe names.
    var documentTitle: String?
    var siteName: String?
    var hostName: String?
    var author: String?
    var imageURL: URL?
    var sourceURL: URL?

    init(page: HTMLPage, url: URL?) {
        let host = url?.host()?.replacingOccurrences(of: "www.", with: "")
        hostName = host
        siteName = page.meta("og:site_name", "application-name", "apple-mobile-web-app-title").map(ImportText.inline)
        documentTitle = page.meta("og:title", "twitter:title") ?? page.title
        let rawAuthor = page.meta("author", "article:author", "parsely-author", "sailthru.author")
        author = rawAuthor.flatMap { $0.hasPrefix("http") ? nil : ImportText.inline($0) }

        let canonical = ImportText.url(page.canonicalURL ?? page.meta("og:url"), relativeTo: url)
        if let canonical, url != nil, canonical.host()?.replacingOccurrences(of: "www.", with: "") == host {
            sourceURL = canonical
        } else {
            sourceURL = url ?? canonical
        }
        imageURL = ImportText.url(page.meta("og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src"), relativeTo: sourceURL)

        // The recipe's own heading: the longest <h1> (or <h2>) that the document title contains.
        let pageTitles = [page.meta("og:title"), page.title].compactMap { $0 }.map(ImportText.normalizedForComparison)
        let headings = page.lines.filter { ($0.headingLevel ?? 9) <= 2 && $0.text.count <= 120 }
        let matching = headings
            .filter { heading in
                let key = ImportText.normalizedForComparison(heading.text)
                return key.count >= 3 && pageTitles.contains { $0.contains(key) }
            }
            .max { $0.text.count < $1.text.count }
        if let matching {
            title = ImportText.stripRecipeSuffix(matching.text)
        } else if let documentTitle {
            title = ImportText.cleanTitle(documentTitle, siteName: siteName, host: host)
        } else {
            title = headings.first { $0.headingLevel == 1 }.map { ImportText.stripRecipeSuffix($0.text) } ?? ""
        }
    }

    /// "Serves 4", "Yield: 4 servings", "Servings: 4-6", or "Yield" followed by "4 servings".
    func yield(near span: ClosedRange<Int>, in lines: [PageLine]) -> String? {
        let pattern = #"^(yields?|serves|servings|makes|portions)\b"#
        let candidates = lines.indices.filter { lines[$0].text.count <= 60 && lines[$0].text.lowercased().range(of: pattern, options: .regularExpression) != nil }
        let nearest = candidates.min { abs($0 - span.lowerBound) < abs($1 - span.lowerBound) }
        guard let index = nearest else { return nil }
        let text = lines[index].text
        let stripped = text.replacingOccurrences(of: #"^(yields?|servings)\s*:?\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        if stripped.isEmpty, index + 1 < lines.count {
            return lines[index + 1].text
        }
        // "Serves 6 | Level: Beginner" keeps only the yield.
        return text.components(separatedBy: " | ").first?.replacingOccurrences(of: #"^(yields?|servings)\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// "Prep time: 25 minutes", "Total Time: 5 days", "Active Time: 4 hrs".
    func times(in lines: [PageLine]) -> (prep: Duration?, cook: Duration?, total: Duration?) {
        var prep: Duration?
        var cook: Duration?
        var total: Duration?
        for line in lines where line.text.count <= 80 {
            let lower = line.text.lowercased()
            guard let colon = lower.firstIndex(of: ":") else { continue }
            let label = lower[..<colon].trimmingCharacters(in: .whitespaces)
            let value = String(lower[lower.index(after: colon)...])
            switch label {
            case "prep", "prep time", "preparation time", "active time", "hands-on time":
                prep = prep ?? TextDuration.parse(value)
            case "cook", "cook time", "cooking time", "bake time", "baking time":
                cook = cook ?? TextDuration.parse(value)
            case "total", "total time", "ready in":
                total = total ?? TextDuration.parse(value)
            default:
                continue
            }
        }
        return (prep, cook, total)
    }
}

// MARK: - Microdata

/// schema.org Recipe microdata: `itemprop="recipeIngredient"` (or the older `ingredients`),
/// `recipeInstructions`, `name`, `recipeYield`, times, `image` and `author`.
enum MicrodataRecipe {
    static func read(_ properties: [MicrodataProperty], base: URL?) -> ImportedRecipe? {
        let inRecipe = properties.filter { $0.scopeType?.lowercased().hasSuffix("/recipe") == true }
        let ingredientValues = inRecipe.filter { $0.name == "recipeIngredient" || $0.name == "ingredients" }.map(\.value)
        let ingredients = ImportText.ingredientList(ingredientValues)
        guard ingredients.lines.count >= 2 else { return nil }

        func first(_ name: String) -> String? {
            inRecipe.first { $0.name == name && !$0.value.isEmpty }?.value
        }
        var steps = inRecipe.filter { $0.name == "recipeInstructions" }.flatMap { ImportText.steps(from: $0.value) }
        if steps.isEmpty {
            // Instructions as nested HowToStep items, each with its own `text`.
            steps = properties
                .filter { $0.scopeType?.lowercased().hasSuffix("/howtostep") == true && $0.name == "text" }
                .flatMap { ImportText.steps(from: $0.value) }
        }
        let author = first("author") ?? properties.first {
            $0.name == "name" && $0.scopeType?.lowercased().hasSuffix("/person") == true
        }?.value
        func duration(_ name: String) -> Duration? {
            first(name).flatMap { ISO8601Duration.parse($0) ?? TextDuration.parse($0) }
        }
        return ImportedRecipe(
            title: first("name").map(ImportText.inline) ?? "",
            ingredients: ingredients.lines,
            steps: steps.map { ImportedStep(text: $0) },
            yield: first("recipeYield").map(YieldText.strippingLabel),
            author: author.map(ImportText.inline),
            imageURL: ImportText.url(first("image"), relativeTo: base),
            prepTime: duration("prepTime"),
            cookTime: duration("cookTime"),
            totalTime: duration("totalTime"),
            category: first("recipeCategory").map(ImportText.inline),
            cuisine: first("recipeCuisine").map(ImportText.inline),
            ingredientGroups: ingredients.groups,
            method: .microdata,
            confidence: 0.85
        )
    }
}
