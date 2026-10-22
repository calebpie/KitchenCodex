import Foundation
import Units

/// What a page is, once read. A recipe page yields one or more recipes; any other kind says why
/// it is not a recipe (`PageReading.reason`).
public enum PageKind: String, Sendable, Codable, CaseIterable {
    case recipe
    case contents
    case index
    case sources
    /// A photo plate: a picture with little or no text.
    case photo
    /// Running prose with no ingredients or steps: an essay, a chapter opener, a technique.
    case prose
    case blank
    /// Too little text could be read.
    case unreadable
}

/// Why scan review would be asked for (04 §5.1 "Scan review", 02 Flow B step 5). The raw values are
/// what `RecipeVersion.reviewReasons` stores.
public enum ReviewReason: String, Sendable, Codable, CaseIterable, Comparable {
    /// The first recipe captured from a book confirms how the book lays a recipe out.
    case firstRecipeOfBook
    /// A layout signature the cook has not confirmed for this book (`Book.reviewedLayouts`).
    case unseenLayout
    case lowOCRConfidence
    /// Ingredient lines the parser could not read into an amount and an item.
    case unparsedIngredients
    /// The steps read do not match the page: numbered steps with one missing, or the recognizer's
    /// paragraphs and the reading's steps far apart.
    case stepCountDisagrees
    /// Text or a picture inside the recipe that the structurer could not assign.
    case unassignedRegion

    public static func < (lhs: ReviewReason, rhs: ReviewReason) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// The reason in a few words, for the review screen and the report.
    public var label: String {
        switch self {
        case .firstRecipeOfBook: "first recipe from this book"
        case .unseenLayout: "a layout not yet confirmed"
        case .lowOCRConfidence: "low OCR confidence"
        case .unparsedIngredients: "ingredient lines that didn't parse"
        case .stepCountDisagrees: "step count disagrees with the page"
        case .unassignedRegion: "a region nothing claimed"
        }
    }
}

/// One ingredient line read off a page.
public struct PageIngredient: Sendable, Equatable {
    /// The line as printed, a wrapped line rejoined, OCR's fraction slips mended ("13/4" → "1 3/4").
    public var text: String
    public var parsed: ParsedIngredient
    /// The group heading above it on the page ("Sauce", "For the dressing").
    public var group: String?
    /// How sure the parser is: 1 for an amount, a unit and an item; less for a counted item, a line
    /// with no amount, or one that did not parse.
    public var confidence: Double
    /// The line did not read into an amount and an item where it seems to have one (a stray digit
    /// left in the item, an empty item), or it is too long for an ingredient line.
    public var isUnparsed: Bool
    /// The block it came from.
    public var block: Int

    public init(text: String, parsed: ParsedIngredient, group: String? = nil, confidence: Double, isUnparsed: Bool, block: Int) {
        self.text = text
        self.parsed = parsed
        self.group = group
        self.confidence = confidence
        self.isUnparsed = isUnparsed
        self.block = block
    }
}

/// One step as printed: a paragraph of the method, never split or merged (04 §5.1 "Step
/// granularity"); a paragraph broken by a column or a page turn is rejoined, since it is one
/// paragraph in print.
public struct PageStep: Sendable, Equatable {
    public var text: String
    /// The number printed before it, when the book numbers its steps.
    public var number: Int?
    /// The blocks it came from.
    public var blocks: [Int]
    /// A printed process photo next to it: a candidate for the step's photo (a "Step photo" region
    /// in review, 04 §2 Phase 2).
    public var photo: Int?

    public init(text: String, number: Int? = nil, blocks: [Int], photo: Int? = nil) {
        self.text = text
        self.number = number
        self.blocks = blocks
        self.photo = photo
    }
}

/// A pointer to another page: "see page 88", "Herb Butter (page 214)", "PHOTOGRAPH ON PAGE 6".
/// Detected and listed; linking is slice 6's (Flow B step 6).
public struct PageCrossReference: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable {
        /// A recipe named in an ingredient or step: a component to link.
        case recipe
        /// The book's Sources or Resources page.
        case sources
        case photograph
        /// A method or technique described elsewhere ("see page 88 for a quicker method").
        case technique
    }

    public var kind: Kind
    /// The phrase as printed.
    public var phrase: String
    public var pages: [Int]
    /// The recipe or thing referred to, when the line names it ("Herb Butter").
    public var target: String?

    public init(kind: Kind, phrase: String, pages: [Int], target: String? = nil) {
        self.kind = kind
        self.phrase = phrase
        self.pages = pages
        self.target = target
    }
}

/// How sure each stage was, 0…1.
public struct PageConfidence: Sendable, Equatable {
    /// The recognizer's mean line confidence over the recipe's lines, as Vision reports it (the
    /// document reader rarely reports over 0.75 for clean print).
    public var ocr: Double
    /// Share of ingredient lines that read cleanly.
    public var parser: Double
    /// How complete the structure is: a title, ingredients, steps, a yield, nothing unassigned.
    public var structure: Double
    /// The model's own figure, when it was asked.
    public var model: Double?

    public init(ocr: Double, parser: Double, structure: Double, model: Double? = nil) {
        self.ocr = ocr
        self.parser = parser
        self.structure = structure
        self.model = model
    }

    /// OCR rescaled so clean print reads near 1 (Vision's document reader tops out around 0.7).
    public var ocrScore: Double { min(1, max(0, (ocr - 0.25) / 0.40)) }

    /// The recipe's figure, `Recipe.extractionConfidence`: the stages weighted, and a model reading
    /// held at or under the model's own figure.
    public var combined: Double {
        let value = 0.25 * ocrScore + 0.35 * parser + 0.40 * structure
        if let model { return min(value, model) }
        return value
    }
}

/// One recipe read off a page (or a spread, once stitched).
public struct PageRecipe: Sendable {
    public var title: String
    /// The yield as printed ("Makes 2 to 4 servings", "Serves 4").
    public var yield: String?
    public var prepTime: Duration?
    public var cookTime: Duration?
    public var totalTime: Duration?
    public var headnote: String?
    public var ingredients: [PageIngredient]
    public var steps: [PageStep]
    /// Asides printed after the method ("note …").
    public var notes: [String]
    public var crossReferences: [PageCrossReference]
    /// Column count, block order and type sizes, for `Book.reviewedLayouts`.
    public var layoutSignature: String
    public var confidence: PageConfidence
    /// The page's printed step numbers disagree with the steps read, or the recognizer's paragraphs
    /// and the steps read are far apart.
    public var stepCountDisagrees: Bool
    /// Text or photo blocks inside the recipe nothing claimed.
    public var unassignedBlocks: [Int]
    /// The first step begins mid-paragraph: the page continues one before it.
    public var startsMidStep: Bool
    /// The last step stops mid-sentence: it continues on the next page.
    public var endsMidStep: Bool
    /// `.pageText` for the deterministic reading, `.model` once the on-device model refined it.
    public var method: ImportMethod

    public init(title: String = "", yield: String? = nil, headnote: String? = nil, ingredients: [PageIngredient] = [], steps: [PageStep] = [], notes: [String] = [], crossReferences: [PageCrossReference] = [], layoutSignature: String = "", confidence: PageConfidence = PageConfidence(ocr: 0, parser: 0, structure: 0), stepCountDisagrees: Bool = false, unassignedBlocks: [Int] = [], startsMidStep: Bool = false, endsMidStep: Bool = false, method: ImportMethod = .pageText) {
        self.title = title
        self.yield = yield
        self.headnote = headnote
        self.ingredients = ingredients
        self.steps = steps
        self.notes = notes
        self.crossReferences = crossReferences
        self.layoutSignature = layoutSignature
        self.confidence = confidence
        self.stepCountDisagrees = stepCountDisagrees
        self.unassignedBlocks = unassignedBlocks
        self.startsMidStep = startsMidStep
        self.endsMidStep = endsMidStep
        self.method = method
    }

    public var unparsedIngredientCount: Int { ingredients.count(where: \.isUnparsed) }

    /// Whether the reading stands on its own: a title, at least two ingredients and a step (the web
    /// importer's `isComplete`). The on-device model is asked only when it does not (slice 10's
    /// rule).
    public var isComplete: Bool { !title.isEmpty && ingredients.count >= 2 && !steps.isEmpty }

    /// The reasons review would be forced or suggested, given the book: whether it has a recipe
    /// already, and the layouts the cook has confirmed.
    public func reviewReasons(bookHasRecipes: Bool, reviewedLayouts: Set<String>) -> [ReviewReason] {
        var reasons: [ReviewReason] = []
        if !bookHasRecipes { reasons.append(.firstRecipeOfBook) }
        if !reviewedLayouts.contains(layoutSignature) { reasons.append(.unseenLayout) }
        if confidence.ocr < PageStructurer.lowOCR { reasons.append(.lowOCRConfidence) }
        if unparsedIngredientCount > 0 { reasons.append(.unparsedIngredients) }
        if stepCountDisagrees { reasons.append(.stepCountDisagrees) }
        if !unassignedBlocks.isEmpty { reasons.append(.unassignedRegion) }
        return reasons
    }

    /// The reading as the importer's draft, which the app already knows how to save.
    public var draft: ImportedRecipe {
        var groups: [Int: String] = [:]
        var previous: String?
        for (index, ingredient) in ingredients.enumerated() where ingredient.group != previous {
            if let group = ingredient.group { groups[index] = group }
            previous = ingredient.group
        }
        var recipe = ImportedRecipe(
            title: title,
            ingredients: ingredients.map(\.text),
            steps: steps.map { ImportedStep(text: $0.text) },
            yield: yield,
            prepTime: prepTime,
            cookTime: cookTime,
            totalTime: totalTime,
            ingredientGroups: groups,
            method: method,
            confidence: confidence.combined
        )
        recipe.headnote = headnote
        recipe.notes = notes
        return recipe
    }
}

/// Everything read from one page, or from consecutive pages stitched into one reading.
public struct PageReading: Sendable {
    /// The files read, in order (one, or several for a stitched recipe).
    public var files: [String]
    /// Every block, in reading order, with its role; a stitched reading's later pages' blocks carry
    /// their `file`.
    public var blocks: [PageBlock]
    public var kind: PageKind
    /// Why the page is not a recipe ("a contents page: 42 entries with page numbers"); nil for a
    /// recipe.
    public var reason: String?
    /// The recipes on the page, in reading order; most pages have one, some two or three.
    public var recipes: [PageRecipe]
    /// The page number read off each page (a folio or running head), nil where none was found.
    public var pageNumbers: [Int?]
    /// The gate's reading of each page, when it was run.
    public var quality: [PageQualityReading?]
    /// Mean recognizer confidence over the page's text.
    public var ocrConfidence: Double
    /// The page has no title and continues a recipe from the page before.
    public var isContinuation: Bool
    /// Time to read (OCR and structure), per page.
    public var durations: [Duration]
    /// Quarter turns counterclockwise each page was read at beyond its EXIF orientation
    /// (`PageScan.quarterTurns`): 0 for a page shot upright, 1 or 3 for a book turned sideways, 2
    /// for one upside down. The blocks' rects are in the turned frame, so a page scan stored upright
    /// matches them.
    public var quarterTurns: [Int] = []
    /// What a page of reference reading holds (`ReferenceReader`), for a page of kind `.prose`
    /// that reads as a glossary, a chapter opener or a technique; nil otherwise.
    public var reference: ImportedReference?
    /// The page's outline in the frame the blocks are in, found for a contents or index page so
    /// its reader can drop what lies beside the book (ux-notes row 119); nil otherwise.
    public var outline: PageQuad?

    public init(files: [String], blocks: [PageBlock], kind: PageKind, reason: String? = nil, recipes: [PageRecipe] = [], pageNumbers: [Int?] = [], quality: [PageQualityReading?] = [], ocrConfidence: Double = 0, isContinuation: Bool = false, durations: [Duration] = []) {
        self.files = files
        self.blocks = blocks
        self.kind = kind
        self.reason = reason
        self.recipes = recipes
        self.pageNumbers = pageNumbers
        self.quality = quality
        self.ocrConfidence = ocrConfidence
        self.isContinuation = isContinuation
        self.durations = durations
    }

    /// The first page's number.
    public var pageNumber: Int? { pageNumbers.compactMap { $0 }.first }

    /// The page's layout signature: its first recipe's.
    public var layoutSignature: String? { recipes.first?.layoutSignature }
}
