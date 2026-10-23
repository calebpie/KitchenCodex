import Foundation

/// Turns a page's blocks into recipes, deterministically (04 §1: deterministic first, model second).
///
/// - Margins: text off the page, the facing page's edge, text inside a printed photo and the
///   recognizer's low-confidence scraps are ignored; running heads and folios are furniture, and the
///   folio's number is the page number.
/// - Kind: a contents or index page (lines ending in page numbers), a Sources page, a photo plate,
///   a blank or unreadable page each say so; everything else is read for recipes.
/// - Titles: text set clearly larger than the body, or letterspaced capitals heavy enough to head a
///   recipe (size × letter width) and centred over what follows. Each title starts a recipe, so a
///   page with two recipes reads as two; text before the first title continues the page before.
/// - Ingredients: runs of short lines that parse as an amount and an item (`IngredientParser`),
///   with bare items ("Kosher salt") and group headings ("SAUCE", "Dressing") inside a run, and
///   wrapped lines (a hanging indent, or a lowercase line after a comma) rejoined.
/// - Steps: the method's printed paragraphs in reading order, never split or merged: a paragraph
///   starts at a first-line indent, a gap, a step number, a run-in head ("TO SERVE:") or after a
///   short last line; a paragraph the recognizer split, or one that runs on into the next column,
///   is one step.
/// - Headnote: prose before the ingredients, or the first paragraphs after them that do not read as
///   instructions. Yield and times from their phrases; "PHOTOGRAPH ON PAGE 6" and "(page 214)" are
///   cross-references; a printed photo beside a step is that step's photo candidate.
public struct PageStructurer: Sendable {
    /// Mean OCR confidence under which review is asked for. Vision's document reader reports about
    /// 0.55–0.70 for clean print photographed well.
    public static let lowOCR = 0.45
    /// Size over the body text that marks a title on its own.
    static let titleSize = 1.3
    /// Size × letter width over the body's that marks a title set larger and looser than the body.
    static let titleWeight = 2.2
    /// Size × letter width over the body's for letterspaced capitals at the top of a column: a
    /// title, where a component heading lower down ("CARROTS") is not.
    static let spacedTitleWeight = 1.85

    public init() {}

    /// The page number among lines read from a page's margins: the first folio, never a
    /// cross-reference ("PHOTOGRAPH ON PAGE 31") or a yield.
    public static func folioNumber(in lines: [String]) -> Int? {
        for line in lines {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.count <= 40, !PageLines.isYield(text), !PageLines.isCrossReferenceLine(text),
                  text.range(of: #"\bpages?\b"#, options: [.regularExpression, .caseInsensitive]) == nil else { continue }
            if let number = Page.folioNumber(text) { return number }
        }
        return nil
    }

    public func read(_ scan: PageScan, file: String = "", quality: PageQualityReading? = nil) -> PageReading {
        var page = Page(scan: scan)
        page.markNoise()
        let pageNumber = page.markFurniture()
        page.markContinuedLines()
        page.markDropCaps()

        var reading = PageReading(files: [file], blocks: [], kind: .recipe, pageNumbers: [pageNumber], quality: [quality], ocrConfidence: page.ocrConfidence, durations: [scan.duration])
        reading.quarterTurns = [scan.quarterTurns]
        reading.pageNumberConfidence = page.folioConfidence
        if let (kind, reason) = page.nonRecipeKind() {
            reading.kind = kind
            reading.reason = reason
            if kind == .contents || kind == .index, page.bareFolio { reading.pageNumbers = [nil] }
            reading.blocks = page.blocks
            return reading
        }

        let titles = page.findTitles()
        var recipes: [PageRecipe] = []
        var recipeBlocks: [[Int]] = []
        for segment in page.segments(titles: titles) {
            guard let recipe = page.structure(segment) else { continue }
            // Before the first title, a scrap (a sticky note read as a step) is no recipe.
            if recipe.title.isEmpty, recipe.ingredients.isEmpty, recipe.steps.reduce(0, { $0 + $1.text.count }) < 80 {
                continue
            }
            guard !(recipe.ingredients.isEmpty && recipe.steps.isEmpty) else { continue }
            recipes.append(recipe)
            recipeBlocks.append((segment.title?.blocks ?? []) + segment.blocks)
        }
        // Each block knows its recipe, so review can show one recipe's regions on a shared page.
        for (recipe, ids) in recipeBlocks.enumerated() {
            for id in ids { page.blocks[id].recipe = recipe }
        }
        // A printed "continued" line (ux-notes row 131): the recipe at the page's head carries on
        // the page before; the one at its foot runs over the page.
        if page.continuedAtHead, !recipes.isEmpty { recipes[0].continuesFromPage = true }
        if page.continuedAtFoot, !recipes.isEmpty { recipes[recipes.count - 1].continuesOverPage = true }
        reading.blocks = page.blocks
        reading.secondLanguage = page.secondLanguage
        // Reference reading (slice 7): a glossary, a chapter opener or a technique, which a recipe
        // with no ingredients on this page would otherwise be read as.
        if let reference = ReferenceReader.read(blocks: page.blocks, recipes: recipes, isContinuation: recipes.first?.title.isEmpty == true) {
            reading.kind = .prose
            reading.reason = reference.reason
            reading.reference = reference
            return reading
        }
        if recipes.isEmpty {
            let characters = page.contentCharacters
            reading.kind = characters > 300 ? .prose : .unreadable
            reading.reason = characters > 300
                ? "running prose with no ingredients or steps (\(characters) characters): an essay, a technique or a chapter opener"
                : "too little text to read (\(characters) characters)"
            return reading
        }
        reading.recipes = recipes
        reading.isContinuation = recipes.first?.title.isEmpty == true
        return reading
    }
}

// MARK: - The page being read

private struct Page {
    var blocks: [PageBlock]
    let paper: PageRect?
    /// Share of the image that is paper.
    let paperFraction: Double
    /// The page itself: the rows and columns that are mostly paper.
    let pageCore: PageRect?
    /// The body text's line height and letter width.
    var body: Double
    var bodyGlyph: Double
    /// Letter width over line height of the page's running text: a paragraph set noticeably wider
    /// is set heavier (a bold headnote beside a roman method).
    var proseWeight: Double
    /// Drop caps waiting to be put back: the paragraph's block and the letter.
    var dropCaps: [Int: String] = [:]
    /// Whether the page number came from a folio with no separator ("60" alone, "Pickled Beets 60"),
    /// which on a contents or index page is as likely an entry's page.
    var bareFolio = false
    var bareNumbers: Set<Int> = []
    /// A paragraph's first line read together with its drop cap ("Few thangs are as gaod…"): set
    /// large, level with the lines beside it.
    var dropCapLines: Set<Int> = []
    /// The recognizer's confidence in the folio line the page number came from.
    var folioConfidence: Double?
    /// The second language a title's alternate name read as ("fr"), when one did.
    var secondLanguage: String?
    /// A printed "continued" line at the page's head or foot (ux-notes row 131).
    var continuedAtHead = false
    var continuedAtFoot = false

    init(scan: PageScan) {
        blocks = scan.blocks
        paper = scan.paper
        paperFraction = scan.paperFraction
        pageCore = scan.pageCore
        let prose = scan.blocks.filter { $0.kind != .photo && $0.role != .ignore }.flatMap(\.lines).filter { $0.text.count >= 25 }
        let sizes = prose.map(\.size).sorted()
        body = sizes.isEmpty ? 0.012 : sizes[sizes.count / 2]
        let glyphs = prose.map { $0.rect.width / Double($0.text.count) }.sorted()
        bodyGlyph = glyphs.isEmpty ? 0.006 : glyphs[glyphs.count / 2]
        let weights = prose.map { Self.weight(of: $0) }.sorted()
        proseWeight = weights.isEmpty ? 0.5 : weights[weights.count / 2]
    }

    static func weight(of line: PageTextLine) -> Double {
        (line.rect.width / Double(max(1, line.text.count))) / max(line.size, 0.001)
    }

    /// Mean letter width over line height across a paragraph's longer lines.
    func weight(of lines: [PageTextLine]) -> Double? {
        let long = lines.filter { $0.text.count >= 20 }
        guard !long.isEmpty else { return nil }
        return long.map(Self.weight(of:)).reduce(0, +) / Double(long.count)
    }

    var textIndices: [Int] {
        blocks.indices.filter { blocks[$0].kind != .photo && blocks[$0].role != .ignore }
    }

    var ocrConfidence: Double {
        let lines = textIndices.flatMap { blocks[$0].lines }
        guard !lines.isEmpty else { return 0 }
        return lines.map(\.confidence).reduce(0, +) / Double(lines.count)
    }

    var contentCharacters: Int {
        textIndices.filter { blocks[$0].role != .furniture }.reduce(0) { $0 + blocks[$1].characterCount }
    }

    // MARK: Noise

    mutating func markNoise() {
        let photos = blocks.filter { $0.kind == .photo }.map(\.rect)
        for index in textIndices {
            let block = blocks[index]
            // The recognizer's scraps: a word off the cutting mat, a smudge read as letters.
            if block.confidence < 0.22, block.characterCount < 30 { blocks[index].role = .ignore; continue }
            // Text inside a printed photo (a label on a bottle).
            if photos.contains(where: { block.rect.coverage(by: $0) > 0.6 }) { blocks[index].role = .ignore; continue }
            let letters = block.text.filter(\.isLetter)
            if letters.isEmpty, block.text.count > 3, !block.text.contains(where: \.isNumber) { blocks[index].role = .ignore }
        }
        // The cutting mat's print above the page.
        if let core = pageCore {
            for index in textIndices where blocks[index].rect.maxY < core.minY + 0.005 && blocks[index].rect.coverage(by: core) < 0.5 {
                blocks[index].role = .ignore
            }
        }
        // The facing page's edge: narrow scraps entirely outside where most of the text is.
        let text = textIndices.map { blocks[$0] }
        let total = text.reduce(0) { $0 + $1.characterCount }
        guard total > 0 else { return }
        func edge(_ sorted: [PageBlock], value: (PageBlock) -> Double) -> Double {
            var running = 0
            for block in sorted {
                running += block.characterCount
                if Double(running) >= Double(total) * 0.08 { return value(block) }
            }
            return value(sorted.last!)
        }
        let left = edge(text.sorted { $0.rect.minX < $1.rect.minX }) { $0.rect.minX }
        let right = edge(text.sorted { $0.rect.maxX > $1.rect.maxX }) { $0.rect.maxX }
        for index in textIndices {
            let rect = blocks[index].rect
            let nearEdge = rect.minX < 0.08 || rect.maxX > 0.92
            if nearEdge, rect.width < 0.12, rect.maxX < left - 0.005 || rect.minX > right + 0.005 {
                blocks[index].role = .ignore
            }
        }
    }

    // MARK: Furniture and the page number

    /// Marks running heads and folios; returns the page number read off a folio.
    mutating func markFurniture() -> Int? {
        let text = textIndices
        guard let top = text.map({ blocks[$0].rect.minY }).min(), let bottom = text.map({ blocks[$0].rect.maxY }).max() else { return nil }
        let band = max(0.04, (bottom - top) * 0.10)
        var numbers: [(Int, Double, Bool, Double)] = []
        bareFolio = false
        for index in text {
            let block = blocks[index]
            guard block.lines.count <= 2, block.characterCount <= 50 else { continue }
            let inBottom = block.rect.minY >= bottom - band
            let inTop = block.rect.maxY <= top + band
            guard inBottom || inTop else { continue }
            let line = block.text.trimmingCharacters(in: .whitespaces)
            if PageLines.isYield(line) || PageLines.isCrossReferenceLine(line) { continue }
            if line.range(of: #"\$\s?\d"#, options: .regularExpression) != nil {
                blocks[index].role = .ignore
                continue
            }
            let small = block.typeSize <= body * 0.9
            let apart = gapToNeighbours(index) >= body * 1.2
            var folio = Self.folioNumber(line)
            if folio != nil, line.allSatisfy(\.isNumber), aloneOnItsLine(index) == false {
                // A contents page's page numbers sit at the end of their entries.
                folio = nil
                continue
            }
            if folio != nil, small || apart {
                blocks[index].role = .furniture
                if let number = folio {
                    numbers.append((number, block.rect.minX, inBottom, block.confidence))
                    if line.range(of: #"[|/·•\-–—]"#, options: .regularExpression) == nil { bareNumbers.insert(number) }
                }
            } else if apart, small || block.typeSize <= body * 1.1, !line.hasSuffix("."),
                      PageLines.ingredientShape(line) != .strong(1), !(PageLines.titleText(line) != line && blockWeight(block) >= Self.headingWeight) {
                // A running head or a lone page number set apart in the margin.
                blocks[index].role = .furniture
            }
        }
        // A folio just past the paper as measured (a page's foot in shadow), set aside as off the
        // page by the reader.
        if numbers.isEmpty {
            for index in blocks.indices where blocks[index].role == .ignore && blocks[index].kind != .photo && blocks[index].lines.count == 1 {
                let rect = blocks[index].rect
                guard rect.minX > 0.01, rect.maxX < 0.99, rect.minY > 0.01, rect.maxY < 0.99,
                      let paper, rect.minY < paper.maxY + 0.12, rect.maxY > paper.minY - 0.12,
                      rect.minY > paper.maxY - 0.02 || rect.maxY < paper.minY + 0.02 else { continue }
                let line = blocks[index].text.trimmingCharacters(in: .whitespaces)
                guard !line.allSatisfy(\.isNumber), let number = Self.folioNumber(line) else { continue }
                blocks[index].role = .furniture
                numbers.append((number, rect.minX, rect.minY > paper.maxY - 0.02, blocks[index].confidence))
                if line.range(of: #"[|/·•\-–—]"#, options: .regularExpression) == nil { bareNumbers.insert(number) }
                break
            }
        }
        // The running head set on the folio's line goes with it.
        for index in text where blocks[index].role == nil && blocks[index].lines.count == 1 && blocks[index].characterCount <= 30 {
            let rect = blocks[index].rect
            if text.contains(where: { blocks[$0].role == .furniture && blocks[$0].rect.verticalOverlap(with: rect) > 0.4 && blocks[$0].rect.distance(to: rect) < 0.3 }) {
                blocks[index].role = .furniture
            }
        }
        // A bottom folio beats a top one; on a spread the left page's comes first.
        let chosen = numbers.sorted { ($0.2 ? 0 : 1, $0.1) < ($1.2 ? 0 : 1, $1.1) }.first
        let number = chosen?.0
        folioConfidence = chosen?.3
        bareFolio = number.map(bareNumbers.contains) ?? false
        return number
    }

    /// A printed "continued" line, with the title or without, is furniture (ux-notes row 131), and
    /// says which way the recipe runs: at the page's head it carries on the page before, at its
    /// foot it runs over the page.
    mutating func markContinuedLines() {
        let text = textIndices.filter { blocks[$0].role != .furniture }
        guard let top = text.map({ blocks[$0].rect.minY }).min(), let bottom = text.map({ blocks[$0].rect.maxY }).max(), bottom > top else { return }
        for index in textIndices where blocks[index].lines.count <= 2 && blocks[index].characterCount <= 90 {
            guard PageLines.isContinuedLine(blocks[index].text) else { continue }
            blocks[index].role = .furniture
            if blocks[index].rect.midY < top + (bottom - top) * 0.5 { continuedAtHead = true } else { continuedAtFoot = true }
        }
    }

    static let headingWeight = 1.8

    /// Nothing else on the same line across the page but a running head ("21  small plates").
    func aloneOnItsLine(_ index: Int) -> Bool {
        let rect = blocks[index].rect
        return !textIndices.contains { other in
            guard other != index, blocks[other].rect.verticalOverlap(with: rect) > 0.4, blocks[other].rect.distance(to: rect) < 0.3 else { return false }
            let text = blocks[other].text
            let runningHead = blocks[other].lines.count == 1 && text.count <= 30 && !text.contains(where: \.isNumber)
                && blocks[other].typeSize <= body * 1.1
            return !runningHead
        }
    }

    /// Vertical distance to the nearest other text block that overlaps it across.
    func gapToNeighbours(_ index: Int) -> Double {
        let rect = blocks[index].rect
        var nearest = 1.0
        for other in textIndices where other != index && blocks[other].role != .furniture {
            let candidate = blocks[other].rect
            // Not what shares its line (a folio's running head), only what is above or below.
            guard candidate.verticalOverlap(with: rect) < 0.3 else { continue }
            guard candidate.horizontalOverlap(with: rect) > 0 || candidate.distance(to: rect) < 0.05 else { continue }
            let gap = max(candidate.minY - rect.maxY, rect.minY - candidate.maxY)
            nearest = min(nearest, max(0, gap))
        }
        return nearest
    }

}

extension Page {
    /// "47", "46 / KITCHEN", "SAUCES & PICKLES / 47", "Vegetables | 15", "16 | Grains", "14 small
    /// plates", "small plates 17", "SMALL PLATES · 16", "INTRODUCTION · xii", and a margin crop's
    /// "• 17" (the separator read on its own with the number, ux-notes row 160).
    static func folioNumber(_ text: String) -> Int? {
        // A separator read ahead of the number goes; one after it stays ("513-" is no folio).
        let line = text.replacingOccurrences(of: #"^[\s•·|/–—-]+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if let match = line.firstMatch(of: /^(\d{1,3})$/) { return Int(match.output.1) }
        // The separator is sometimes read as a 1, l, I or ! ("Soups 1 41" for "Soups | 41").
        if let match = line.firstMatch(of: /^(\d{1,3})\s*(?:[|\/·•\-–—]|\s[1lI!]\s)?\s*[A-Za-z][A-Za-z &',.’\-]{2,30}$/) { return Int(match.output.1) }
        if let match = line.firstMatch(of: /^[A-Za-z][A-Za-z &',.’]{2,30}?\s*(?:[|\/·•\-–—]|\s[1lI!]\s)?\s*(\d{1,3})$/) { return Int(match.output.1) }
        if let match = line.firstMatch(of: /^[A-Za-z][A-Za-z &',.’]{2,30}?\s*[|\/·•\-–—]\s*([ivxlc]{1,7})$/) { return romanValue(String(match.output.1)) }
        return nil
    }

    static func romanValue(_ text: String) -> Int? {
        let values: [Character: Int] = ["i": 1, "v": 5, "x": 10, "l": 50, "c": 100]
        var total = 0, previous = 0
        for character in text.lowercased().reversed() {
            guard let value = values[character] else { return nil }
            total += value < previous ? -value : value
            previous = max(previous, value)
        }
        return total > 0 ? total : nil
    }

    // MARK: Drop caps

    mutating func markDropCaps() {
        for index in textIndices where blocks[index].role == nil && blocks[index].lines.count == 1 {
            let block = blocks[index]
            guard block.typeSize >= body * 1.8, block.text.split(separator: " ").count >= 3, besideText(index) else { continue }
            dropCapLines.insert(index)
        }
        for index in textIndices where blocks[index].role == nil {
            let block = blocks[index]
            let text = block.text.trimmingCharacters(in: .whitespaces)
            guard text.count <= 2, text.allSatisfy(\.isLetter), block.typeSize >= body * 1.6 else { continue }
            blocks[index].role = .ignore
            // The paragraph it opens: the line just to its right, level with its top.
            let neighbour = textIndices.filter { $0 != index && blocks[$0].role == nil }
                .filter {
                    let first = blocks[$0].lines.first?.rect ?? blocks[$0].rect
                    return first.minX >= block.rect.maxX - 0.01 && first.minX - block.rect.maxX < 0.05 && first.verticalOverlap(with: block.rect) > 0.2
                }
                .min { blocks[$0].rect.minY < blocks[$1].rect.minY }
            if let neighbour { dropCaps[neighbour] = text }
        }
    }

    // MARK: Kind

    func nonRecipeKind() -> (PageKind, String)? {
        let content = textIndices.filter { blocks[$0].role != .furniture }
        let characters = content.reduce(0) { $0 + blocks[$1].characterCount }
        let lines = content.flatMap { blocks[$0].lines.map(\.text) }
        let photoArea = blocks.filter { $0.kind == .photo }.reduce(0) { $0 + $1.rect.area }
        let paperArea = paper?.area ?? 1
        let strong = lines.count { if case .strong = PageLines.ingredientShape($0) { true } else { false } }

        let pictured = photoArea > paperArea * 0.15 || paper == nil || paperFraction < 0.8
        if characters < 15 {
            if pictured { return (.photo, "a photo plate: no text beside the picture") }
            return (.blank, "no text on the page")
        }
        // Contents and index: lines ending in page numbers, or columns of bare numbers.
        let entries = lines.count { line in
            line.range(of: #"[A-Za-z].*\D\s*\d{1,3}$"#, options: .regularExpression) != nil
                || line.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil
                || line.range(of: #"^[ivxlc]{1,6}$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let lowerText = lines.joined(separator: "\n").lowercased()
        let commaLists = lines.count { $0.range(of: #",\s*\d{1,3}(\s*[,–-]\s*\d{1,3})+\s*$"#, options: .regularExpression) != nil }
        let topLines = content.sorted { blocks[$0].rect.minY < blocks[$1].rect.minY }.prefix(3).map { blocks[$0].text.lowercased().trimmingCharacters(in: .whitespaces) }
        // An index prints a comma before each page ("clafoutis, 280"), and often "Index" in its
        // running head or foot ("INDEX – 333"), which the structurer may have set aside as furniture.
        let commaPages = lines.count { $0.range(of: #"[\p{L}\)],\s*\d{1,3}(\s*[–-]\s*\d{1,3})?$"#, options: .regularExpression) != nil }
        let byHeight = textIndices.sorted { blocks[$0].rect.minY < blocks[$1].rect.minY }
        let runningIndex = [byHeight.first, byHeight.last].compactMap(\.self).contains { index in
            blocks[index].text.lowercased().range(of: #"^\s*index\b[^a-z0-9]*\d{1,3}\s*$|^\s*\d{1,3}[^a-z0-9]*\bindex\s*$"#, options: .regularExpression) != nil
        }
        if topLines.contains("index") || commaLists >= 6 || runningIndex && commaPages >= 4 || commaPages >= 8 && commaPages * 2 >= entries {
            if entries + commaLists >= 8 { return (.index, "an index page: \(entries + commaLists) entries with page numbers") }
        }
        if entries >= 8, Double(entries) >= Double(lines.count) * 0.35, strong < 4 || Double(entries) > Double(strong) * 2 {
            return (.contents, "a contents page: \(entries) entries with page numbers")
        }
        if lowerText.range(of: #"(^|\n)\s*contents\s*(\n|$)"#, options: .regularExpression) != nil, entries >= 4 {
            return (.contents, "a contents page: \(entries) entries with page numbers")
        }
        if lowerText.range(of: #"(^|\n)\s*(sources|resources|suppliers)\s*(\n|$)"#, options: .regularExpression) != nil {
            let contacts = lines.count { $0.range(of: #"(www\.|\.com|\.net|\(\d{3}\)|\d{3}[-.\s]\d{3}[-.\s]\d{4})"#, options: [.regularExpression, .caseInsensitive]) != nil }
            if contacts >= 2 { return (.sources, "a Sources page: \(contacts) suppliers' phone numbers or websites") }
        }
        if characters < 150, strong < 2 {
            if pictured { return (.photo, "a photo plate: \(characters) characters of caption beside the picture") }
            if ocrConfidence < 0.35 { return (.unreadable, "too little text could be read (\(characters) characters, OCR \(String(format: "%.2f", ocrConfidence)))") }
            return (.blank, "almost no text (\(characters) characters)")
        }
        return nil
    }

    // MARK: Titles

    struct Title {
        var blocks: [Int]
        var text: String
        var isWide: Bool
    }

    func blockWeight(_ block: PageBlock) -> Double {
        guard let line = block.lines.first, !line.text.isEmpty else { return 0 }
        let glyph = (line.rect.width / Double(line.text.count)) / bodyGlyph
        return (line.size / body) * glyph
    }

    func isCaps(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return letters.count >= 3 && letters.allSatisfy { !$0.isLowercase }
    }

    /// Blocks just below `rect` that overlap it across: what a heading heads.
    func region(below rect: PageRect) -> PageRect? {
        let below = textIndices.filter { blocks[$0].role == nil || blocks[$0].role == .ingredient }
            .map { blocks[$0].rect }
            .filter { $0.minY > rect.minY + 0.005 && $0.minY < rect.maxY + 0.2 && $0.horizontalOverlap(with: rect) > 0 }
        guard let first = below.first else { return nil }
        return below.dropFirst().reduce(first) { $0.union($1) }
    }

    mutating func findTitles() -> [Title] {
        var candidates: [(index: Int, wide: Bool)] = []
        for index in textIndices where blocks[index].role == nil {
            let block = blocks[index]
            let text = block.text.trimmingCharacters(in: .whitespaces)
            guard block.lines.count <= 3, (3...100).contains(text.count), text.filter(\.isLetter).count >= 3 else { continue }
            // Letterspaced capitals read with low confidence; a scrap reads with none.
            guard block.confidence >= 0.2 else { continue }
            // Titles open with a capital or a number; a line starting lowercase is a paragraph's
            // first line read apart (a drop cap's "f all the soups…").
            guard let first = text.first, !first.isLowercase else { continue }
            if PageLines.isYield(text) || PageLines.isCrossReferenceLine(text) || PageLines.runInHead(text) != nil { continue }
            if case .strong = PageLines.ingredientShape(text) { continue }
            if text.hasSuffix("."), text.split(separator: " ").count > 3 { continue }
            // A drop cap read into its first line ("Few thangs are as gaod…") sits level with the
            // paragraph it opens; a title stands clear of the text beside it.
            if besideText(index) || !onPage(index) { continue }
            let size = block.typeSize / body
            let weight = blockWeight(block)
            let spaced = isCaps(text) && (block.lines.first.map { ($0.rect.width / Double(max(1, $0.text.count))) / bodyGlyph } ?? 0) >= 1.8
            if size >= PageStructurer.titleSize || (weight >= PageStructurer.titleWeight && size >= 1.15) {
                candidates.append((index, spaced))
            } else if isCaps(text), weight >= PageStructurer.spacedTitleWeight, nothingAbove(index) {
                candidates.append((index, true))
            }
        }
        // A title's second line, set like the first but lighter than a title on its own
        // ("WITH BROWN BUTTER—AU BEURRE NOISETTE" under "SAUTÉED TROUT").
        var extended: [(index: Int, wide: Bool)] = []
        for candidate in candidates {
            extended.append(candidate)
            var last = candidate.index
            for next in textIndices where next > last && blocks[next].role == nil && !candidates.contains(where: { $0.index == next }) {
                let line = blocks[next]
                let text = line.text
                guard line.lines.count <= 2, text.count <= 80, isCaps(text) == isCaps(blocks[candidate.index].text),
                      line.rect.minY - blocks[last].rect.maxY < body * 1.2, line.rect.minY > blocks[last].rect.minY,
                      line.rect.horizontalOverlap(with: blocks[last].rect) > 0.5,
                      blockWeight(line) >= blockWeight(blocks[candidate.index]) * 0.75 else { break }
                extended.append((next, candidate.wide))
                last = next
            }
        }
        candidates = extended
        // Join a title's lines (a two-line title, a title and its subtitle), and a one-line title
        // the recognizer read as two blocks side by side, as a phone reads a long one (ux-notes
        // row 63): the second half level with the first and close across.
        var titles: [Title] = []
        for (index, wide) in candidates {
            if var last = titles.last, let previous = last.blocks.last,
               blocks[index].rect.minY - blocks[previous].rect.maxY < body * 1.6,
               blocks[index].rect.horizontalOverlap(with: blocks[previous].rect) > 0 || abs(blocks[index].rect.midX - blocks[previous].rect.midX) < 0.05
                || isLevelHalf(index, of: previous) {
                last.blocks.append(index)
                last.isWide = last.isWide || wide
                titles[titles.count - 1] = last
            } else {
                titles.append(Title(blocks: [index], text: "", isWide: wide))
            }
        }
        // A second-language name leaves the title and stays in the regions (ux-notes row 59); a
        // kept second name's dash is set off (row 69).
        let language = PageLines.readerLanguage
        for index in titles.indices {
            let parts = titles[index].blocks.flatMap { blocks[$0].lines.map { $0.text.trimmingCharacters(in: .whitespaces) } }
            titles[index].text = PageLines.mendTitleDash(PageLines.titleText(PageLines.titleWithoutAlternate(parts, pageLanguage: language)))
            if secondLanguage == nil, let alternate = PageLines.alternateLanguage(parts, pageLanguage: language) { secondLanguage = alternate.rawValue }
            for block in titles[index].blocks { blocks[block].role = .title }
        }
        return titles
    }

    /// `index` is the second half of a one-line title whose first half is `previous`: set in
    /// title type, level with it, and starting close after its end.
    func isLevelHalf(_ index: Int, of previous: Int) -> Bool {
        let rect = blocks[index].rect, first = blocks[previous].rect
        guard rect.verticalOverlap(with: first) > 0.3, rect.minX > first.minX, rect.minX - first.maxX < body * 3 else { return false }
        return blocks[index].typeSize >= body * PageStructurer.titleSize && blocks[previous].typeSize >= body * PageStructurer.titleSize
    }

    /// Another text block level with it and beside or under it. A block set in title type level
    /// with it is the other half of its own line, not text beside it.
    func besideText(_ index: Int) -> Bool {
        let rect = blocks[index].rect
        let titleType = blocks[index].typeSize >= body * PageStructurer.titleSize
        return textIndices.contains { other in
            guard other != index, blocks[other].role == nil else { return false }
            let candidate = blocks[other].rect
            if titleType, blocks[other].typeSize >= body * PageStructurer.titleSize, candidate.verticalOverlap(with: rect) > 0.3 { return false }
            return candidate.verticalOverlap(with: rect) > 0.3 && candidate.distance(to: rect) < body * 1.5
                && candidate.minY > rect.minY + rect.height * 0.25
        }
    }

    /// No content text above it in its column: it heads the column.
    func nothingAbove(_ index: Int) -> Bool {
        let rect = blocks[index].rect
        return !textIndices.contains { other in
            guard other != index, blocks[other].role == nil, onPage(other) else { return false }
            let candidate = blocks[other].rect
            return candidate.maxY <= rect.minY + 0.002 && candidate.horizontalOverlap(with: rect) > 0.1
                && rect.minY - candidate.maxY < 0.25
        }
    }

    /// On the page itself rather than the margin of the photo around it (the cutting mat's logo).
    func onPage(_ index: Int) -> Bool {
        guard let core = pageCore else { return true }
        return blocks[index].rect.coverage(by: core) >= 0.5
    }

    // MARK: Segments

    /// Blocks per recipe, in reading order: one segment per title, and one before the first title
    /// when the page opens mid-recipe.
    func segments(titles: [Title]) -> [(title: Title?, blocks: [Int])] {
        var result: [(title: Title?, blocks: [Int])] = [(nil, [])]
        let starts = Dictionary(uniqueKeysWithValues: titles.map { ($0.blocks[0], $0) })
        for index in blocks.indices {
            if let title = starts[index] {
                result.append((title, []))
                continue
            }
            let role = blocks[index].role
            guard role != .ignore, role != .furniture, role != .title else { continue }
            result[result.count - 1].blocks.append(index)
        }
        return result.filter { $0.title != nil || !$0.blocks.isEmpty }
    }

    // MARK: One recipe

    struct Line {
        var block: Int
        var line: PageTextLine
        var text: String
    }

    mutating func structure(_ segment: (title: Title?, blocks: [Int])) -> PageRecipe? {
        var recipe = PageRecipe(title: segment.title?.text ?? "")
        var lines: [Line] = []
        var photos: [Int] = []
        var crossReferences: [PageCrossReference] = []
        var headnoteLead: [String] = []

        for index in segment.blocks {
            let block = blocks[index]
            if block.kind == .photo { photos.append(index); continue }
            let text = block.text.trimmingCharacters(in: .whitespaces)
            if block.lines.count <= 2, PageLines.isYield(text), !text.contains("/") {
                blocks[index].role = .yield
                recipe.yield = recipe.yield ?? PageLines.yieldText(text)
                continue
            }
            if block.lines.count <= 2, PageLines.isCrossReferenceLine(text) {
                blocks[index].role = .crossReference
                crossReferences += PageCrossReferences.find(in: text, kind: .photograph)
                continue
            }
            if block.lines.count == 1, let time = PageLines.time(text) {
                blocks[index].role = .time
                switch time.kind {
                case "prep": recipe.prepTime = time.duration
                case "cook": recipe.cookTime = time.duration
                default: recipe.totalTime = time.duration
                }
                continue
            }
            for (number, line) in block.lines.enumerated() {
                var text = line.text
                if number == 0, let letter = dropCaps[index], text.first?.isLowercase == true || text.first == " " {
                    text = letter + text
                }
                if number == 0, let (yield, rest) = PageLines.leadingYield(text) {
                    recipe.yield = recipe.yield ?? PageLines.yieldText(yield)
                    text = rest
                    headnoteLead.append(contentsOf: [])
                }
                lines.append(Line(block: index, line: line, text: text))
            }
        }

        // Ingredients: runs of list lines.
        let proseBlocks = Set(segment.blocks.filter { isProse(blocks[$0]) })
        var roles = [LineRole](repeating: .prose, count: lines.count)
        var ingredients: [(text: String, group: String?, block: Int, head: Int)] = []
        var group: String?
        var index = 0
        var inRun = false
        var runStart = 0
        var runStrong = 0
        var runFirstIngredient = 0
        var runs: [ClosedRange<Int>] = []
        func closeRun(at end: Int) {
            guard inRun else { return }
            inRun = false
            // A run needs two lines that read as ingredients (or one and a bare item).
            let count = ingredients.count - runFirstIngredient
            if runStrong >= 2 || (runStrong >= 1 && count >= 2) {
                runs.append(runStart...max(runStart, end))
            } else {
                for position in runStart...max(runStart, end) where position < roles.count { roles[position] = .prose }
                ingredients.removeLast(count)
            }
        }
        while index < lines.count {
            let current = lines[index]
            if proseBlocks.contains(current.block) || dropCaps[current.block] != nil {
                closeRun(at: index - 1)
                index += 1
                continue
            }
            // A clear break down the page (the rule under an ingredient band) ends a run.
            if inRun, index > 0, current.line.rect.minY - lines[index - 1].line.rect.maxY >= body * 2.5 {
                closeRun(at: index - 1)
            }
            let shape = PageLines.ingredientShape(current.text)
            let next = index + 1 < lines.count && !proseBlocks.contains(lines[index + 1].block) ? PageLines.ingredientShape(lines[index + 1].text) : .not
            // A wrapped line: a hanging indent, or a lowercase line after a comma or an open clause.
            if inRun, let last = ingredients.last, index > 0, roles[index - 1] == .ingredient,
               isContinuation(current, of: lines[last.head], previous: lines[index - 1], shape: shape) {
                ingredients[ingredients.count - 1].text = PageText.join([ingredients[ingredients.count - 1].text, current.text])
                roles[index] = .ingredient
                index += 1
                continue
            }
            // A heading in capitals or with a colon is plain; a lowercase one ("Dressing",
            // "stock", "Pickling liquid") is short and needs a break above it inside a list, or it
            // is a bare item ("Freshly ground black pepper", "Vegetable oil for frying").
            let marked = isCaps(current.text) || current.text.hasSuffix(":")
            let words = current.text.split(separator: " ").map { $0.lowercased() }
            // …and names a part of the recipe, not a pantry staple ("Canola oil", "Kosher salt").
            let staples: Set<String> = ["oil", "salt", "pepper", "butter", "sugar", "flour", "milk", "cream", "water", "juice", "zest", "vinegar", "garlic", "eggs", "honey"]
            let plainHeading = words.count <= 3 && !words.contains { ["for", "of", "to", "and", "or", "with"].contains($0) || staples.contains($0) }
            let sameColumnBreak = index > 0 && current.line.rect.horizontalOverlap(with: lines[index - 1].line.rect) > 0.3
                && current.line.rect.minY - lines[index - 1].line.rect.maxY >= body * 0.9
            let columnTop = index > 0 && current.line.rect.horizontalOverlap(with: lines[index - 1].line.rect) < 0.1
                && current.line.rect.minY < lines[index - 1].line.rect.minY
            let headingLike = PageLines.couldBeGroupHeading(current.text)
                && (next != .not) && (marked || shape == .bare || shape == .not)
                && (marked || (plainHeading && (!inRun || sameColumnBreak || columnTop)))
            // A break in a column with no heading after it ends the group above it.
            if inRun, sameColumnBreak, !headingLike { group = nil }
            if headingLike, next != .bare || marked {
                if !inRun { inRun = true; runStart = index; runStrong = 0; runFirstIngredient = ingredients.count }
                group = PageLines.titleText(ImportText.groupName(current.text))
                roles[index] = .group
                index += 1
                continue
            }
            switch shape {
            case .strong:
                if !inRun { inRun = true; runStart = index; runStrong = 0; runFirstIngredient = ingredients.count; if runs.isEmpty { group = nil } }
                runStrong += 1
                ingredients.append((current.text, group, current.block, index))
                roles[index] = .ingredient
            case .bare:
                if inRun || next != .not {
                    if !inRun { inRun = true; runStart = index; runStrong = 0; runFirstIngredient = ingredients.count }
                    ingredients.append((current.text, group, current.block, index))
                    roles[index] = .ingredient
                } else {
                    roles[index] = .prose
                }
            case .not:
                // A long last item set like the rest ("sprigs of fresh dill (see page 120),
                // for garnish"): no sentence, no verb first, right under the line before.
                let words = current.text.split(separator: " ").count
                if inRun, words <= 12, !(current.text.last.map { ".!?".contains($0) } ?? false),
                   !PageLines.opensWithVerb(current.text), !PageLines.readsAsInstruction(current.text) || current.text.first?.isLowercase == true,
                   gapBefore(index, in: lines) < body * 0.8, index > 0, roles[index - 1] == .ingredient,
                   !proseBlocks.contains(current.block) {
                    ingredients.append((current.text, group, current.block, index))
                    roles[index] = .ingredient
                } else {
                    closeRun(at: index - 1)
                    roles[index] = .prose
                }
            }
            index += 1
        }
        closeRun(at: lines.count - 1)

        for item in ingredients {
            let text = PageLines.ingredientText(item.text)
            let parsed = IngredientParser.parse(text)
            let unparsed = PageLines.isUnparsed(text, parsed: parsed)
            recipe.ingredients.append(PageIngredient(text: text, parsed: parsed, group: item.group, confidence: PageLines.parserConfidence(parsed, unparsed: unparsed), isUnparsed: unparsed, block: item.block))
            crossReferences += PageCrossReferences.find(in: text, kind: .recipe)
        }
        for (position, line) in lines.enumerated() {
            switch roles[position] {
            case .ingredient: blocks[line.block].role = blocks[line.block].role ?? .ingredient
            case .group: blocks[line.block].role = blocks[line.block].role ?? .ingredientGroup
            case .prose, .label: break
            }
        }
        for (number, ingredient) in recipe.ingredients.enumerated() where blocks[ingredient.block].item == nil {
            blocks[ingredient.block].item = number
        }

        // A "note" label set beside its first line (and often read after it) opens that line's note.
        for (position, label) in lines.enumerated() where roles[position] == .prose
            && label.text.trimmingCharacters(in: .whitespaces).range(of: #"^(notes?|tip):?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let rect = label.line.rect
            if let target = lines.indices.first(where: { other in
                other != position && roles[other] == .prose && lines[other].line.rect.verticalOverlap(with: rect) > 0.4
                    && lines[other].line.rect.minX > rect.maxX - 0.005 && lines[other].line.rect.minX - rect.maxX < 0.1
            }) {
                lines[target].text = "note " + lines[target].text
                roles[position] = .label
                blocks[label.block].role = .note
            }
        }

        // The method: prose lines, broken into printed paragraphs, the ingredient runs as hard breaks.
        let firstRun = runs.first?.lowerBound ?? lines.count
        var parts: [[Int]] = [[]]
        for position in lines.indices {
            if roles[position] != .prose {
                if !(parts.last?.isEmpty ?? true) { parts.append([]) }
                continue
            }
            parts[parts.count - 1].append(position)
        }
        var paragraphs: [(lines: [Int], beforeIngredients: Bool, opensWithBreak: Bool, part: Int)] = []
        for (partIndex, part) in parts.enumerated() where !part.isEmpty {
            for paragraph in self.paragraphs(part.map { lines[$0] }, positions: part) {
                paragraphs.append((paragraph.lines, paragraph.lines.first! < firstRun, paragraph.startsCleanly, partIndex))
            }
        }
        var previousWasHeadnote = false
        var previousPart = -1

        var sawStep = false
        var headnoteWeight: Double?
        var numbered = false
        var visionBlocksInSteps = Set<Int>()
        var stepLineRects: [[PageRect]] = []
        // The ingredient column's extent across, for a step set beside it (ux-notes row 166).
        let ingredientRectsRead = lines.indices.filter { roles[$0] == .ingredient }.map { lines[$0].line.rect }
        let ingredientBox: PageRect? = ingredientRectsRead.first.map { first in ingredientRectsRead.dropFirst().reduce(first) { $0.union($1) } }
        for (number, paragraph) in paragraphs.enumerated() {
            let text = PageText.join(paragraph.lines.map { lines[$0].text })
            guard text.filter(\.isLetter).count >= 2 else { continue }
            let blockIDs = Array(NSOrderedSet(array: paragraph.lines.map { lines[$0].block })) as? [Int] ?? []
            let hasDropCap = paragraph.lines.first.map {
                (dropCaps[lines[$0].block] != nil && lines[$0].line == blocks[lines[$0].block].lines.first) || dropCapLines.contains(lines[$0].block)
            } ?? false
            if PageLines.isNote(text) {
                recipe.notes.append(PageLines.noteText(text))
                blockIDs.forEach { blocks[$0].role = blocks[$0].role ?? .note }
                continue
            }
            let instruction = PageLines.readsAsInstruction(text)
            let continuesPrevious = number == 0 && segment.title == nil && !paragraph.opensWithBreak
            let marked = PageLines.runInHead(text) != nil || PageLines.stepNumber(text) != nil
            // Prose before the ingredients is the headnote (unless it is marked as a step, or the
            // recipe has no ingredients here, as on a page that continues one); after them, the
            // paragraphs before the first instruction that read as the cook talking are.
            let headnote: Bool
            let paragraphRect = paragraph.lines.map { lines[$0].line.rect }.dropFirst().reduce(lines[paragraph.lines[0]].line.rect) { $0.union($1) }
            if sawStep || continuesPrevious || marked {
                headnote = false
            } else if paragraph.beforeIngredients, let ingredientBox, paragraphRect.minX >= ingredientBox.maxX - 0.02,
                      instruction, PageLines.opensWithVerb(text), !PageLines.readsAsHeadnote(text) {
                // A step set in a column beside the ingredients, read before them (a method that
                // runs on at the top right of the page, ux-notes row 166): the method's, not the
                // headnote's.
                headnote = false
            } else if recipe.headnote != nil, previousWasHeadnote, previousPart == paragraph.part, text.first?.isLowercase == true {
                // The rest of a headnote paragraph the recognizer split ("in the same pot. I make…").
                headnote = true
            } else if recipe.headnote != nil, !paragraph.beforeIngredients, !instruction {
                // The headnote's later paragraphs ("Buy the smallest leeks you can find…"),
                // until the method's first instruction.
                headnote = true
            } else if recipe.headnote != nil, !paragraph.beforeIngredients, let headnoteWeight, headnoteWeight >= proseWeight * 1.08,
                      let weight = weight(of: paragraph.lines.map { lines[$0].line }),
                      weight >= proseWeight * 1.08 {
                // Advice in the headnote's heavier type ("Use the freshest fish you
                // can find…") is still the headnote, though it reads as an instruction.
                headnote = true
            } else if hasDropCap {
                // A drop cap opens the headnote; the method never starts with one.
                headnote = true
            } else if paragraph.beforeIngredients, !runs.isEmpty, segment.title != nil {
                headnote = true
            } else if paragraph.beforeIngredients, segment.title != nil, !instruction {
                headnote = true
            } else {
                headnote = !instruction && (hasDropCap || PageLines.readsAsHeadnote(text) || text.first?.isLowercase == true)
            }
            previousWasHeadnote = headnote
            previousPart = paragraph.part
            if headnote {
                if headnoteWeight == nil { headnoteWeight = weight(of: paragraph.lines.map { lines[$0].line }) }
                recipe.headnote = recipe.headnote.map { $0 + "\n\n" + text } ?? text
                blockIDs.forEach { blocks[$0].role = blocks[$0].role ?? .headnote }
                crossReferences += PageCrossReferences.find(in: text, kind: .recipe)
                continue
            }
            sawStep = true
            var stepText = text
            var stepNumber: Int?
            let expectedNumber = recipe.steps.count + 1
            if let (value, rest) = PageLines.stepNumber(text), (1...40).contains(value) {
                // The numeral as printed, in sequence or not: a gap or a repeat in the run is what
                // says the steps disagree with the page (ux-notes row 124).
                stepNumber = value
                stepText = rest
                numbered = true
            } else if let match = text.firstMatch(of: /^(.+?)\s+(\d{1,2})$/), let value = Int(match.output.2), value == expectedNumber, paragraph.lines.count >= 2,
                      lines[paragraph.lines.last!].text.trimmingCharacters(in: .whitespaces) == String(value) {
                // The step's number read after its text, as a line of its own.
                stepNumber = value
                stepText = String(match.output.1)
                numbered = true
            }
            if number == 0, segment.title == nil, !paragraph.opensWithBreak { recipe.startsMidStep = true }
            recipe.steps.append(PageStep(text: stepText, number: stepNumber, blocks: blockIDs))
            stepLineRects.append(paragraph.lines.map { lines[$0].line.rect })
            blockIDs.forEach { visionBlocksInSteps.insert($0) }
            crossReferences += PageCrossReferences.find(in: stepText, kind: .recipe)
        }
        // The method's steps in print order (ux-notes row 166): by their printed numerals when
        // every step carries one, else column by column, each column read to its foot before the
        // next, so a method set in two columns beside the ingredients reads as printed.
        let order = PageStructurer.stepOrder(recipe.steps, rects: stepLineRects)
        if order != Array(recipe.steps.indices) {
            recipe.steps = order.map { recipe.steps[$0] }
            stepLineRects = order.map { stepLineRects[$0] }
        }
        for (number, step) in recipe.steps.enumerated() {
            for block in step.blocks where blocks[block].role == nil || blocks[block].role == .step {
                blocks[block].role = .step
                if blocks[block].item == nil { blocks[block].item = number }
            }
        }
        if let last = recipe.steps.last?.text, let end = last.last, !".!?)”\"".contains(end) {
            recipe.endsMidStep = true
        }

        // Step photos: a printed photo next to a step.
        var unassigned: [Int] = []
        for photo in photos {
            let rect = blocks[photo].rect
            // The nearest step that the photo lines up with across (a process photo under the method
            // column) or sits right beside.
            let nearest = stepLineRects.enumerated().map { step, rects -> (Int, Double) in
                let distance = rects.map { line in
                    line.horizontalOverlap(with: rect) > 0.3 || line.verticalOverlap(with: rect) > 0.3 ? line.distance(to: rect) : 1
                }.min() ?? 1
                return (step, distance)
            }.min { $0.1 < $1.1 }
            if let (step, distance) = nearest, distance <= 0.2 {
                if recipe.steps[step].photo == nil { recipe.steps[step].photo = photo }
                blocks[photo].role = .stepPhoto
                blocks[photo].item = step
            } else {
                unassigned.append(photo)
            }
        }
        // Text nothing claimed.
        for index in segment.blocks where blocks[index].kind != .photo && blocks[index].role == nil {
            if blocks[index].text.filter(\.isLetter).count >= 3 { unassigned.append(index) }
        }
        recipe.unassignedBlocks = unassigned
        recipe.crossReferences = Self.unique(crossReferences)

        // Step count against the page: only a broken run of printed numerals, a gap or a repeat,
        // says the steps read disagree with it (ux-notes row 124); the largest numeral differing
        // from the count read does not, as a numeral misread, or one read off a time or a page
        // pointer, would.
        let numbers = recipe.steps.compactMap(\.number)
        if !numbers.isEmpty {
            recipe.stepCountDisagrees = zip(numbers, numbers.dropFirst()).contains { $1 != $0 + 1 }
        } else if !recipe.steps.isEmpty {
            // The recognizer splits printed paragraphs more often than it joins them, so its count
            // runs high; far more, or fewer than the steps read, means the paragraphs are in doubt.
            let recognized = visionBlocksInSteps.count
            recipe.stepCountDisagrees = recognized + 1 < recipe.steps.count || recognized > recipe.steps.count * 2 + 2
        }

        // Signature and confidence.
        let segmentRects = segment.blocks.map { blocks[$0].rect } + (segment.title?.blocks.map { blocks[$0].rect } ?? [])
        let region = segmentRects.dropFirst().reduce(segmentRects.first ?? .zero) { $0.union($1) }
        let ingredientRects = lines.indices.filter { roles[$0] == .ingredient }.map { lines[$0].line.rect }
        let ingredientTop = ingredientRects.map(\.minY).min() ?? 1
        let headnoteBelow = paragraphs.filter { paragraph in
            !paragraph.beforeIngredients && paragraph.lines.allSatisfy { blocks[lines[$0].block].role == .headnote }
        }.flatMap(\.lines).map { lines[$0].line.rect }.filter { $0.minY > ingredientTop }
        let methodRects = stepLineRects.flatMap { $0 } + headnoteBelow
        recipe.layoutSignature = LayoutSignature.make(.init(
            title: segment.title.map { title in title.blocks.map { blocks[$0].rect }.min { $0.width < $1.width }! }, titleIsWide: segment.title?.isWide ?? false, region: region,
            ingredientLines: ingredientRects, methodLines: methodRects, numbered: numbered
        ))
        let usedLines = lines.map(\.line) + (segment.title?.blocks.flatMap { blocks[$0].lines } ?? [])
        let ocr = usedLines.isEmpty ? 0 : usedLines.map(\.confidence).reduce(0, +) / Double(usedLines.count)
        let parser = recipe.ingredients.isEmpty ? 0 : Double(recipe.ingredients.count { !$0.isUnparsed }) / Double(recipe.ingredients.count)
        var structure = 0.0
        if !recipe.title.isEmpty { structure += 0.25 }
        if recipe.ingredients.count >= 2 { structure += 0.3 }
        if !recipe.steps.isEmpty { structure += 0.3 }
        if recipe.yield != nil { structure += 0.05 }
        if recipe.unassignedBlocks.isEmpty { structure += 0.1 }
        recipe.confidence = PageConfidence(ocr: ocr, parser: parser, structure: structure)
        return recipe
    }

    enum LineRole: Equatable {
        case prose, ingredient, group
        /// A label set apart from the text it introduces ("note").
        case label
    }


    /// A block of running text: several lines with sentences, most of which are not ingredient lines.
    func isProse(_ block: PageBlock) -> Bool {
        guard block.lines.count >= 2 else { return false }
        let text = block.text
        let words = text.split(separator: " ").count
        guard words >= 12, text.contains(". ") || text.hasSuffix(".") else { return false }
        let strong = block.lines.count { if case .strong = PageLines.ingredientShape($0.text) { true } else { false } }
        return Double(strong) < Double(block.lines.count) * 0.5
    }

    func gapBefore(_ position: Int, in lines: [Line]) -> Double {
        guard position > 0 else { return 1 }
        let previous = lines[position - 1].line.rect, current = lines[position].line.rect
        guard current.horizontalOverlap(with: previous) > 0 else { return 1 }
        return current.minY - previous.maxY
    }

    /// A wrapped ingredient line: set in under the line it continues (a hanging indent, even when it
    /// starts with an amount of its own, as "½ cup each of two kinds…" under "1 pound mixed mushrooms—about"),
    /// or a lowercase line after a comma or an open clause.
    func isContinuation(_ line: Line, of head: Line, previous: Line, shape: PageLines.IngredientShape) -> Bool {
        let rect = line.line.rect, headRect = head.line.rect
        guard rect.minY >= headRect.minY, rect.minY - previous.line.rect.maxY < line.line.size * 1.2 else { return false }
        guard rect.horizontalOverlap(with: headRect) > 0.3 else { return false }
        // A tilted page drifts a little from line to line; a wrapped line is set in by an em or so,
        // and one that opens with an amount of its own must be set in plainly.
        let indent = rect.minX - headRect.minX
        let em = max(line.line.size, head.line.size)
        let strong: Bool
        if case .strong = shape { strong = true } else { strong = false }
        if indent >= em * (strong ? 1.0 : 0.6), indent < 0.08 { return true }
        if strong { return false }
        let open = previous.text.range(of: #"([,(\-–—]|\b(and|or|about|plus|with|into|of))$"#, options: .regularExpression) != nil
            || previous.text.filter({ $0 == "(" }).count > previous.text.filter({ $0 == ")" }).count
        return open && line.text.first?.isLowercase == true
    }

    // MARK: Paragraphs

    struct Paragraph {
        var lines: [Int]
        /// The paragraph opened with a clear start (an indent, a number, a head, a gap) rather than
        /// running on from what came before it.
        var startsCleanly: Bool
    }

    /// Printed paragraphs over consecutive prose lines.
    func paragraphs(_ run: [Line], positions: [Int]) -> [Paragraph] {
        guard !run.isEmpty else { return [] }
        // Columns: consecutive lines that overlap across.
        var column = [Int](repeating: 0, count: run.count)
        for index in 1..<max(1, run.count) {
            let previous = run[index - 1].line.rect, current = run[index].line.rect
            let sameColumn = current.horizontalOverlap(with: previous) > 0.3 && current.minY > previous.minY - previous.height * 0.5
            column[index] = sameColumn ? column[index - 1] : column[index - 1] + 1
        }
        // Each column's left edge as a line through its lines' left ends (the page is rarely square),
        // fitted to the lower envelope so first-line indents stand out; its right edge as a high
        // percentile of the lines' right ends.
        var leftFit: [Int: (Double, Double)] = [:]
        var rightFit: [Int: (Double, Double)] = [:]
        var measure: [Int: Double] = [:]
        var justified: [Int: Bool] = [:]
        for id in Set(column) {
            let members = run.indices.filter { column[$0] == id }.map { run[$0].line }
            let rects = members.map(\.rect)
            leftFit[id] = Self.leftEdgeFit(rects)
            // The right edge the same way, fitted to the upper envelope of the lines' right ends.
            let mirrored = Self.leftEdgeFit(rects.map { PageRect(x: -$0.maxX, y: $0.y, width: $0.width, height: $0.height) })
            rightFit[id] = (-mirrored.0, -mirrored.1)
            measure[id] = (rects.map(\.maxX).max() ?? 1) - (rects.map(\.minX).min() ?? 0)
            // Justified when most lines reach the right edge; ragged-right setting stops short.
            let reaching = members.count { line in line.rect.maxX >= rightFit[id]!.0 + rightFit[id]!.1 * line.rect.midY - line.size * 1.2 }
            justified[id] = members.count >= 4 && Double(reaching) >= Double(members.count) * 0.7
        }
        // The usual distance from one line to the next inside a paragraph, from lines the
        // recognizer kept in one block: a paragraph gap is a good deal more.
        // Pitch over line height, so a page photographed at an angle (type larger at the near end)
        // keeps one measure down the column.
        let pitches = run.indices.dropFirst().compactMap { index -> Double? in
            guard run[index].block == run[index - 1].block, column[index] == column[index - 1] else { return nil }
            let pitch = (run[index].line.top - run[index - 1].line.top) / max(run[index - 1].line.size, 0.001)
            return pitch > 0 ? pitch : nil
        }.sorted()
        let usualPitch = pitches.isEmpty ? nil : pitches[pitches.count / 2]
        // A numbered method starts its steps at the numbers.
        let numberedMethod = run.count { PageLines.stepNumber($0.text) != nil } >= 2

        var result: [Paragraph] = []
        for index in run.indices {
            let line = run[index]
            let rect = line.line.rect
            let size = line.line.size
            var starts = index == 0
            var clean = index == 0 && (dropCaps[line.block] != nil)
            let fit = leftFit[column[index]] ?? (rect.minX, 0)
            let indent = rect.minX - (fit.0 + fit.1 * rect.midY)
            var indented = indent >= size * 0.8 && indent < 0.08
            if indented, index > 0, column[index - 1] == column[index] {
                // Lines set in beside a drop cap, one after another, open one paragraph, not each.
                let previous = run[index - 1].line.rect
                let previousIndent = previous.minX - (fit.0 + fit.1 * previous.midY)
                if previousIndent >= size * 0.8, abs(previousIndent - indent) < size * 0.6 { indented = false }
            }
            let numbered = PageLines.stepNumber(line.text) != nil
            let headed = PageLines.runInHead(line.text) != nil
            let note = PageLines.isNote(line.text)
            let dropCapStart = dropCaps[line.block] != nil && blocks[line.block].lines.first == line.line
            if numbered || headed || note || dropCapStart { starts = true; clean = true }
            if indented, !numberedMethod { starts = true; clean = true }
            if index > 0 {
                let previous = run[index - 1]
                if column[index] == column[index - 1] {
                    // Space between paragraphs: a line pitch well over the column's usual one (1.3
                    // times where the recognizer also starts a paragraph, 1.5 otherwise), measured at
                    // the lines' left ends, as a tilted page's line bounds overlap.
                    let pitch = (line.line.top - previous.line.top) / max(previous.line.size, 0.001)
                    let newBlock = line.block != previous.block
                    if let usualPitch, pitch >= usualPitch * (newBlock ? 1.3 : 1.5) { starts = true; clean = true }
                    if usualPitch == nil, newBlock, pitch >= 1.6 { starts = true; clean = true }
                    // A line that stops well short of the measure after a full stop ends its paragraph;
                    // ragged-right setting makes a merely short line no sign of one.
                    let prevEnds = previous.text.last.map { ".!?:)”\"".contains($0) } ?? false
                    let fitRight = rightFit[column[index]].map { $0.0 + $0.1 * previous.line.rect.midY } ?? 1
                    let shortBy = fitRight - previous.line.rect.maxX
                    let prevShort = justified[column[index]] == true ? shortBy > size * 2.5 : shortBy > (measure[column[index]] ?? 0.4) * 0.35
                    if !numberedMethod, prevEnds, prevShort, line.text.first.map({ $0.isUppercase || $0.isNumber }) == true { starts = true; clean = true }
                } else if index == 0 || !starts {
                    // Top of a new column: a paragraph runs on unless this line opens one.
                    let prevEnds = previous.text.last.map { ".!?:)”\"".contains($0) } ?? false
                    let previousRight = rightFit[column[index - 1]].map { $0.0 + $0.1 * previous.line.rect.midY } ?? 1
                    if prevEnds, line.text.first.map({ $0.isUppercase }) == true, !(previous.line.rect.maxX >= previousRight - size * 2.5) {
                        starts = true; clean = true
                    }
                }
            }
            // A paragraph never opens lowercase ("and chill.", "to 350°F."): that is a line of the one
            // before, read apart.
            if starts, index > 0, line.text.first?.isLowercase == true, !numbered, !headed, !note { starts = false; clean = false }
            if starts || result.isEmpty {
                result.append(Paragraph(lines: [positions[index]], startsCleanly: clean || (index == 0 && line.text.first?.isUppercase == true && indented)))
            } else {
                result[result.count - 1].lines.append(positions[index])
            }
        }
        if let first = run.first, result.first?.startsCleanly == false {
            // The first line of a run of prose starts a paragraph unless it reads as a continuation.
            let continues = first.text.first?.isLowercase == true
            result[0].startsCleanly = !continues && (PageLines.readsAsInstruction(first.text) || PageLines.readsAsHeadnote(first.text) || dropCaps[first.block] != nil)
        }
        return result
    }

    /// x = a + b·y along the lines' left ends, robust to the lines that don't reach the edge (first
    /// lines set in, short last lines when mirrored for the right edge): the slope is the median of
    /// the slopes between pairs of lines, and the edge runs along the lowest fifth of what is left.
    static func leftEdgeFit(_ rects: [PageRect]) -> (Double, Double) {
        guard rects.count >= 3 else { return (rects.map(\.minX).min() ?? 0, 0) }
        var slopes: [Double] = []
        for i in rects.indices {
            for j in rects.indices where j > i {
                let dy = rects[j].midY - rects[i].midY
                guard abs(dy) > 0.01 else { continue }
                slopes.append((rects[j].minX - rects[i].minX) / dy)
            }
        }
        slopes.sort()
        let slope = slopes.isEmpty ? 0 : max(-0.3, min(0.3, slopes[slopes.count / 2]))
        let offsets = rects.map { $0.minX - slope * $0.midY }.sorted()
        return (offsets[Int(Double(offsets.count - 1) * 0.2)], slope)
    }

    static func unique(_ references: [PageCrossReference]) -> [PageCrossReference] {
        var seen = Set<String>()
        return references.filter { seen.insert($0.phrase.lowercased()).inserted }
    }
}

extension PageStructurer {
    /// The steps' indices in print order (ux-notes row 166): by numeral when every step has one;
    /// else, where the steps sit in more than one column, column by column (left to right), each
    /// top to bottom; else as read.
    static func stepOrder(_ steps: [PageStep], rects: [[PageRect]]) -> [Int] {
        let indices = Array(steps.indices)
        guard steps.count > 1 else { return indices }
        if steps.allSatisfy({ $0.number != nil }) {
            return indices.sorted { (steps[$0].number!, $0) < (steps[$1].number!, $1) }
        }
        let boxes = rects.map { lines in lines.dropFirst().reduce(lines.first ?? .zero) { $0.union($1) } }
        guard boxes.allSatisfy({ $0.width > 0 }) else { return indices }
        // Columns: groups of steps whose extents across don't overlap.
        var columns: [(minX: Double, maxX: Double)] = []
        for box in boxes.sorted(by: { $0.minX < $1.minX }) {
            let low = box.minX + 0.01, high = max(box.minX + 0.02, box.maxX - 0.01)
            if let last = columns.last, low <= last.maxX {
                columns[columns.count - 1].maxX = max(last.maxX, high)
            } else {
                columns.append((low, high))
            }
        }
        guard columns.count > 1 else { return indices }
        func column(of box: PageRect) -> Int {
            columns.firstIndex { box.midX >= $0.minX - 0.01 && box.midX <= $0.maxX + 0.01 } ?? 0
        }
        return indices.sorted { (column(of: boxes[$0]), boxes[$0].minY, $0) < (column(of: boxes[$1]), boxes[$1].minY, $1) }
    }
}
