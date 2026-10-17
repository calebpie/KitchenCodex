import Foundation
import Units

/// The deterministic fallback for pages without structured data: reads ingredients and steps out of
/// the page's visible text.
///
/// Ingredients are the densest run of lines `IngredientParser` reads as ingredients (an amount and a
/// unit, or a counted item), allowing short unparsed lines ("Kosher salt") and group headings inside
/// the run, with a bonus for runs under an "Ingredients" heading. Steps are the block under a
/// "Directions"/"Method"/"Instructions" heading, or a numbered sequence, or the paragraphs right
/// after the ingredients, in that order of preference.
struct PageTextReader {
    struct Reading {
        var ingredients: [String]
        var groups: [Int: String]
        var steps: [String]
        /// Index range in `lines` the recipe was read from, for the model's context.
        var span: ClosedRange<Int>
        var foundIngredientHeading: Bool
        var foundStepsStructure: Bool
    }

    let lines: [PageLine]
    private let kinds: [Kind]

    init(page: HTMLPage) {
        self.init(lines: page.lines)
    }

    init(lines: [PageLine]) {
        self.lines = Self.mergeSplitIngredients(lines)
        kinds = self.lines.map(Self.kind(of:))
    }

    // MARK: - Line classes

    enum Section: Equatable {
        case ingredients, steps, end
    }

    enum Kind: Equatable {
        /// An ingredient line, with how sure the reading is (1 for amount and unit).
        case ingredient(Double)
        /// Short text with no amount that could be an ingredient inside a run ("Kosher salt").
        case maybeIngredient
        case groupHeading
        case section(Section)
        /// A heading or short line that neither starts nor ends a run (an ad label, "Tip").
        case aside
        /// Sentences.
        case prose
    }

    private static let ingredientHeadings: Set<String> = [
        "ingredients", "ingredient", "ingredient list", "the ingredients", "what you ll need",
        "what you need", "you ll need", "you will need",
    ]
    private static let stepHeadings: Set<String> = [
        "directions", "instructions", "method", "preparation", "steps", "recipe steps", "how to make it",
        "how to make", "procedure", "cooking instructions", "method of preparation", "preparation method",
        "make it", "to make",
    ]
    private static let endHeadings: Set<String> = [
        "notes", "note", "recipe notes", "cook s notes", "cooks notes", "cook s note", "tips", "tips and tricks",
        "nutrition", "nutrition facts", "nutrition information", "comments", "reviews", "ratings", "related",
        "related recipes", "you may also like", "more recipes", "tags", "tagged", "share", "share this",
        "print", "print this recipe", "print recipe", "equipment", "special equipment", "advertisement",
        "yield", "jump to", "leave a comment", "rate this recipe", "about", "about the author", "video",
        "watch", "storage", "make ahead", "faq", "faqs", "read more", "more", "next", "previous",
    ]
    /// Words that mark site furniture rather than recipe text.
    private static let noisePattern = #"newsletter|subscribe|sign up|signup|advertisement|affiliate|cookie|©|copyright|all rights reserved|privacy policy|terms of (use|service)"#

    static func normalizedKey(_ text: String) -> String {
        ImportText.normalizedForComparison(text)
    }

    private func kind(_ index: Int) -> Kind {
        kinds[index]
    }

    static func kind(of line: PageLine) -> Kind {
        let text = line.text
        let key = normalizedKey(text)
        if key.isEmpty { return .aside }

        if key.count <= 32 {
            if ingredientHeadings.contains(key) || (key.hasPrefix("ingredients ") && key.count <= 24) { return .section(.ingredients) }
            if stepHeadings.contains(key) || ["directions ", "instructions ", "method "].contains(where: key.hasPrefix) { return .section(.steps) }
            if endHeadings.contains(key) { return .section(.end) }
        }
        if text.count <= 140, text.lowercased().range(of: noisePattern, options: .regularExpression) != nil {
            return .section(.end)
        }
        if line.isHeading {
            return ImportText.isGroupHeading(text) ? .groupHeading : .aside
        }
        if ImportText.isGroupHeading(text) { return .groupHeading }
        if text.count > 260 { return .prose }

        let words = text.split(whereSeparator: \.isWhitespace).count
        let endsSentence = text.last.map { ".!?".contains($0) } ?? false
        if isFurniture(text) || isYieldLine(text) { return .aside }

        let parsed = IngredientParser.parse(ImportText.ingredientLine(text))
        if parsed.unit == .toTaste, parsed.quantity == nil, words <= 10 {
            return .ingredient(0.9)
        }
        if parsed.quantity != nil, !parsed.item.isEmpty, !isCountedNonIngredient(parsed.item) {
            // An amount and a unit up front make an ingredient even when the line runs long
            // ("5 pounds beef short ribs, bone-in, thinly sliced … (ask your butcher)").
            if parsed.unit != nil, words <= 32, !(endsSentence && words > 20) { return .ingredient(1) }
            if words > 16 || (endsSentence && words > 10) { return .prose }
            return words <= 14 && text.count <= 110 ? .ingredient(0.8) : .prose
        }
        if text.count > 160 { return .prose }
        // A dash or bullet in the amount's place ("- Canola oil, for frying, as needed").
        if parsed.quantity == nil, text.range(of: #"^[-–•]\s"#, options: .regularExpression) != nil, words <= 16, !endsSentence {
            return .ingredient(0.6)
        }
        if parsed.quantity == nil, words <= 8, text.count <= 60, !endsSentence,
           text.contains(where: \.isLetter), !["button", "label", "option", "summary", "legend"].contains(line.tag) {
            return .maybeIngredient
        }
        if words >= 4 { return .prose }
        return .aside
    }

    /// "2 hours ago", "45 minutes", "4 servings", "12 reviews": numbers that aren't amounts.
    private static func isCountedNonIngredient(_ item: String) -> Bool {
        let first = item.lowercased().split(separator: " ").first.map(String.init) ?? ""
        let words: Set<String> = [
            "servings", "serving", "minutes", "minute", "mins", "min", "hours", "hour", "hrs", "hr", "days",
            "day", "weeks", "comments", "comment", "reviews", "review", "ratings", "rating", "votes",
            "photos", "people", "calories", "kcal", "recipes", "results", "items",
            "followers", "likes", "shares", "of", "steps", "ingredients", "new", "best", "ways", "reasons",
            "things", "tips", "easy", "simple",
        ]
        if words.contains(first) { return true }
        let lower = item.lowercased()
        // "4.5 stars", "12 reviews (see all)", but not "star anise".
        if lower.range(of: #"^(stars?|reviews?)( \(.*\))?$"#, options: .regularExpression) != nil { return true }
        return lower.range(of: #"\bago\b"#, options: .regularExpression) != nil
    }

    /// "Serves 4", "Yield: 6", "Makes 2 loaves": metadata, read separately.
    static func isYieldLine(_ text: String) -> Bool {
        text.count <= 40 && text.lowercased().range(of: #"^(serves|yields?|makes|servings)\b"#, options: .regularExpression) != nil
    }

    private static let months = "january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec"

    /// Dates, bylines, share buttons.
    private static func isFurniture(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.range(of: #"^(\#(months))\.? \d{1,2}(,? \d{4})?$"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"^\d{1,2} (\#(months))\.?( \d{4})?$"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"^(by|written by|photo(graph)?s? by|recipe by|updated|published|posted)\b"#, options: .regularExpression) != nil { return true }
        if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") { return true }
        return false
    }

    // MARK: - Merging split lines

    /// Pages that put the amount, the name and the note in separate elements ("6.5 g" / "Szechuan
    /// pepper" / "whole, divided") get them joined back into one line. A lone step number ("1",
    /// "Step 1") followed by a sentence becomes "1. sentence".
    static func mergeSplitIngredients(_ lines: [PageLine]) -> [PageLine] {
        var merged: [PageLine] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let next = index + 1 < lines.count ? lines[index + 1] : nil

            if let next, !next.isHeading, isStepNumber(line.text), looksLikeSentence(next.text) {
                let number = line.text.filter(\.isNumber)
                merged.append(PageLine(text: "\(number). \(next.text)", tag: next.tag, headingLevel: nil, listID: next.listID))
                index += 2
                continue
            }

            if let next, !line.isHeading, !next.isHeading, isAmountOnly(line.text), next.text.count <= 80,
               !isAmountOnly(next.text), next.text.contains(where: \.isLetter) {
                let isDash = line.text.allSatisfy { "-–—•".contains($0) || $0.isWhitespace }
                var text = isDash ? "- \(next.text)" : "\(line.text) \(next.text)"
                index += 2
                // A short lowercase note after the name: "whole, divided", "fresh, peeled".
                if index < lines.count {
                    let note = lines[index]
                    if !note.isHeading, note.text.count <= 60, note.text.first?.isLowercase == true,
                       !isAmountOnly(note.text) {
                        text += ", \(note.text)"
                        index += 1
                    }
                }
                merged.append(PageLine(text: text, tag: next.tag, headingLevel: nil, listID: next.listID ?? line.listID))
                continue
            }

            merged.append(line)
            index += 1
        }
        return merged
    }

    /// "6.5 g", "1", "2 L", "1/2 cup", "-": an amount with nothing after it.
    static func isAmountOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 14 else { return false }
        if trimmed.allSatisfy({ "-–—•".contains($0) || $0.isWhitespace }) { return true }
        let parsed = IngredientParser.parse(trimmed)
        return parsed.quantity != nil && parsed.item.isEmpty
    }

    static func isStepNumber(_ text: String) -> Bool {
        text.range(of: #"^(step\s*)?\d{1,2}[.:)]?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func looksLikeSentence(_ text: String) -> Bool {
        text.count >= 40 && text.split(whereSeparator: \.isWhitespace).count >= 7
    }

    /// "3. Clear out your fridge" → (3, "Clear out your fridge"); "Step 2: Roast" → (2, "Roast").
    static func numberedStep(_ text: String) -> (number: Int, text: String)? {
        guard let range = text.range(of: #"^(step\s*)?(\d{1,2})\s*([.:)]|\s-)\s*"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let prefix = text[range]
        guard let number = Int(prefix.filter(\.isNumber)) else { return nil }
        let rest = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty, rest.first?.isNumber == false else { return nil }
        return (number, rest)
    }

    // MARK: - Reading

    func read() -> Reading? {
        guard let run = bestIngredientRun() else { return nil }
        let stepsResult = findSteps(after: run)
        let lower = min(run.start, stepsResult?.range.lowerBound ?? run.start)
        let upper = max(run.end, stepsResult?.range.upperBound ?? run.end)
        return Reading(
            ingredients: run.items,
            groups: run.groups,
            steps: stepsResult?.steps ?? [],
            span: lower...upper,
            foundIngredientHeading: run.underHeading,
            foundStepsStructure: stepsResult?.structured ?? false
        )
    }

    struct Run {
        var start: Int
        var end: Int
        var items: [String] = []
        var groups: [Int: String] = [:]
        var score = 0.0
        var confidentCount = 0
        var underHeading = false
        var tags: [String: Int] = [:]
        var listIDs: Set<Int> = []

        var dominantTag: String? { tags.max { $0.value < $1.value }?.key }
    }

    private enum Pending {
        case maybe(Int)
        case group(Int)
        case aside
    }

    func bestIngredientRun() -> Run? {
        var runs: [Run] = []
        var current: Run?
        var pending: [Pending] = []
        var headingUntil = -1
        var groupBeforeRun: (index: Int, name: String)?

        func close() {
            guard var run = current else { return }
            // Unparsed lines trailing the run ("to serve:" then "cooked rice", "kimchi") count only
            // when they look like the run's other lines.
            var trailingGroup: String?
            for entry in pending {
                if case .aside = entry { continue }
                if case let .group(index) = entry, trailingGroup == nil {
                    trailingGroup = ImportText.groupName(lines[index].text)
                    continue
                }
                guard case let .maybe(index) = entry else { break }
                let line = lines[index]
                guard line.tag == run.dominantTag, run.listIDs.isEmpty || line.listID.map(run.listIDs.contains) == true else { break }
                if let group = trailingGroup, run.groups.values.contains(group) == false {
                    run.groups[run.items.count] = group
                }
                run.items.append(line.text)
                run.score += 0.3
                run.end = index
            }
            pending = []
            run.groups = run.groups.filter { $0.key < run.items.count }
            runs.append(run)
            current = nil
        }

        for (index, line) in lines.enumerated() {
            let kind = kind(index)
            switch kind {
            case let .ingredient(strength):
                if current == nil {
                    var run = Run(start: index, end: index)
                    run.underHeading = index <= headingUntil
                    if let group = groupBeforeRun, index - group.index == 1 {
                        run.groups[0] = group.name
                        run.start = group.index
                    }
                    current = run
                }
                for entry in pending {
                    switch entry {
                    case let .maybe(i):
                        current!.items.append(lines[i].text)
                        current!.score += 0.3
                    case let .group(i):
                        current!.groups[current!.items.count] = ImportText.groupName(lines[i].text)
                    case .aside:
                        break
                    }
                }
                pending = []
                current!.items.append(line.text)
                current!.score += strength
                current!.confidentCount += 1
                current!.end = index
                current!.tags[line.tag, default: 0] += 1
                if let list = line.listID { current!.listIDs.insert(list) }
                groupBeforeRun = nil

            case .maybeIngredient:
                if current != nil {
                    pending.append(.maybe(index))
                } else if index <= headingUntil {
                    // Right under "Ingredients", an unparsed first line still starts the list.
                    var run = Run(start: index, end: index)
                    run.underHeading = true
                    if let group = groupBeforeRun, index - group.index == 1 { run.groups[0] = group.name }
                    run.items.append(line.text)
                    run.score += 0.3
                    run.tags[line.tag, default: 0] += 1
                    if let list = line.listID { run.listIDs.insert(list) }
                    current = run
                    headingUntil = index + 2
                }

            case .groupHeading:
                if current != nil {
                    pending.append(.group(index))
                } else {
                    groupBeforeRun = (index, ImportText.groupName(line.text))
                    if index <= headingUntil + 1 { headingUntil = index + 2 }
                }

            case .aside:
                if current != nil { pending.append(.aside) }

            case .section(.ingredients):
                close()
                headingUntil = index + 3

            case .section, .prose:
                close()
            }

            if current != nil {
                let asides = pending.filter { if case .aside = $0 { true } else { false } }.count
                let groups = pending.filter { if case .group = $0 { true } else { false } }.count
                if asides > 2 || groups > 1 || pending.count > 10 { close() }
            }
        }
        close()

        for index in runs.indices where runs[index].underHeading {
            runs[index].score += 2
        }
        return runs
            .filter { $0.items.count >= 3 && ($0.confidentCount >= 2 || ($0.underHeading && $0.confidentCount >= 1)) }
            .max { $0.score < $1.score }
    }

    // MARK: - Steps

    struct StepsResult {
        var steps: [String]
        var range: ClosedRange<Int>
        /// Found under a heading or as a numbered sequence, rather than guessed from position.
        var structured: Bool
    }

    func findSteps(after run: Run) -> StepsResult? {
        var attempts: [() -> StepsResult?] = []
        if let heading = lines.indices.first(where: { $0 > run.end && kind($0) == .section(.steps) }) {
            attempts.append { collectSteps(from: heading + 1, limit: lines.count, structured: true) }
        }
        if let first = lines.indices.first(where: { $0 > run.end && Self.numberedStep(lines[$0].text)?.number == 1 }) {
            attempts.append { collectSteps(from: first, limit: lines.count, structured: true) }
        }
        if let heading = lines.indices.last(where: { $0 < run.start && kind($0) == .section(.steps) }) {
            attempts.append { collectSteps(from: heading + 1, limit: run.start, structured: true) }
        }
        attempts.append { collectSteps(from: run.end + 1, limit: lines.count, structured: false) }

        var fallback: StepsResult?
        for attempt in attempts {
            guard let result = attempt(), !result.steps.isEmpty else { continue }
            if result.steps.count >= 2 { return result }
            fallback = fallback ?? result
        }
        return fallback
    }

    private func collectSteps(from start: Int, limit: Int, structured: Bool) -> StepsResult? {
        guard start < limit else { return nil }
        // Numbered mode when the first numbered line comes before any prose.
        var cursor = start
        while cursor < limit, case .aside = kind(cursor) { cursor += 1 }
        if cursor < limit, Self.numberedStep(lines[cursor].text)?.number == 1 {
            return collectNumberedSteps(from: cursor, limit: limit)
        }

        var steps: [String] = []
        var first = start
        var last = start
        var stepTag: String?
        var stepList: Int?
        var shortLines = 0
        for index in start..<limit {
            let line = lines[index]
            let kind = kind(index)
            switch kind {
            case .section(.steps):
                if steps.isEmpty { continue }
                return finish()
            case .section:
                return finish()
            case .ingredient where !steps.isEmpty:
                return finish()
            default:
                break
            }
            if line.isHeading {
                // A sub-heading inside the method ("Make the sauce") is skipped; a long one is a teaser.
                if line.text.count <= 60 { continue }
                if steps.isEmpty { continue }
                return finish()
            }
            let words = line.text.split(whereSeparator: \.isWhitespace).count
            if line.text.count < 25 || words < 4 {
                if !steps.isEmpty {
                    shortLines += 1
                    if shortLines >= 2 { return finish() }
                }
                continue
            }
            if case .ingredient = kind { continue }
            if let tag = stepTag, steps.count >= 2, line.tag != tag || line.listID != stepList {
                return finish()
            }
            if steps.isEmpty { first = index }
            let text = Self.numberedStep(line.text)?.text ?? line.text
            steps.append(contentsOf: StepSplitter.steps(from: text))
            stepTag = stepTag ?? line.tag
            stepList = steps.count == 1 ? line.listID : stepList
            shortLines = 0
            last = index
        }
        return finish()

        func finish() -> StepsResult? {
            steps.isEmpty ? nil : StepsResult(steps: steps, range: first...last, structured: structured)
        }
    }

    /// Steps marked "1.", "2." …: a numbered line starts a step; paragraphs after it are its body;
    /// ingredient lines in between (per-step ingredient lists) are skipped.
    private func collectNumberedSteps(from start: Int, limit: Int) -> StepsResult? {
        var steps: [String] = []
        var expected = 1
        var last = start
        var bodyTag: String?
        let titleTag = lines[start].tag
        let numberedIndices = (start..<limit).filter { Self.numberedStep(lines[$0].text) != nil }

        for index in start..<limit {
            let line = lines[index]
            if let (number, text) = Self.numberedStep(line.text), number == expected {
                steps.append(text)
                expected += 1
                bodyTag = nil
                last = index
                continue
            }
            let kind = kind(index)
            if case .section(let section) = kind, section != .steps { break }
            if case .ingredient = kind { continue }
            let moreAhead = numberedIndices.contains { $0 > index && Self.numberedStep(lines[$0].text)?.number == expected }
            let words = line.text.split(whereSeparator: \.isWhitespace).count
            // Headings, labels ("Tip") and short titles in the step-title style ("Day 5: Two hours
            // active") are not step text.
            if line.isHeading || words < 4 || (line.tag == titleTag && line.text.count < 60) {
                if moreAhead { continue }
                break
            }
            // After the last numbered step, only its own body continues it.
            if !moreAhead {
                if let bodyTag, line.tag != bodyTag { break }
                if bodyTag == nil, line.tag == titleTag { break }
            }
            let separator = steps[steps.count - 1].last.map { ".!?:".contains($0) } == true ? " " : ". "
            steps[steps.count - 1] += separator + line.text
            bodyTag = bodyTag ?? line.tag
            last = index
        }
        return steps.isEmpty ? nil : StepsResult(steps: steps, range: start...last, structured: true)
    }
}
