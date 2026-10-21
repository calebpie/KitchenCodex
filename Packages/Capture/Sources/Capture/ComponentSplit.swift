import Foundation

/// "Split into N recipes" (04 §2 Phase 2, §5.1 "Sub-recipes on one page"; ux-notes row 61): a recipe
/// whose ingredient groups and step groups line up, the same count or matching names, offered as a
/// parent with linked component recipes. Always the cook's call; this only plans it. A component
/// takes its group's ingredient lines and the run of steps its group heads, whole and in order:
/// nothing is renumbered, no step is split or merged.
///
/// Step groups are the steps a source opens with a label ("For the piperade:", "Pickle the daikon:",
/// "To make the besciamella, …"), the sections a page names (JSON-LD `HowToSection`), and, where a
/// group has neither, the first later step that names its ingredient ("Hold an artichoke stem…"
/// under Baby Artichokes). A label printed under every group ("TO COMPLETE:") marks no boundary. A
/// serving or assembly group ("To serve", "Assembling the Lasagne") stays with the parent unless the
/// cook picks it.
public enum ComponentSplit {
    public struct Part: Sendable, Equatable, Identifiable {
        /// The ingredient group's heading as written ("For the vinaigrette").
        public var group: String
        /// The component's title: the heading without its lead words ("Vinaigrette").
        public var title: String
        /// The group's ingredient lines, by index into the recipe's ingredients.
        public var ingredients: [Int]
        /// The run of steps the group heads, by index, consecutive.
        public var steps: [Int]
        /// A recipe of its own unless the cook says otherwise; a serving or assembly group stays.
        public var isComponent: Bool
        /// Its place among the plan's parts.
        public var id: Int
    }

    public struct Plan: Sendable, Equatable {
        public var parts: [Part]
        public var ingredientCount: Int
        public var stepCount: Int

        /// Recipes after a split with the plan's own choices: the parent and its components.
        public var defaultRecipeCount: Int { 1 + parts.count(where: \.isComponent) }

        /// What the parent keeps when `chosen` (indices into `parts`) become components: every other
        /// ingredient line and step, in order.
        public func parent(choosing chosen: Set<Int>) -> (ingredients: [Int], steps: [Int]) {
            let taken = chosen.filter(parts.indices.contains).map { parts[$0] }
            let ingredients = Set(taken.flatMap(\.ingredients)), steps = Set(taken.flatMap(\.steps))
            return ((0..<ingredientCount).filter { !ingredients.contains($0) }, (0..<stepCount).filter { !steps.contains($0) })
        }
    }

    /// The split `ingredientGroups` (each ingredient line's group, nil for none) and `steps` allow,
    /// or nil when they don't line up or nothing would be a component. `stepGroups` are section
    /// names a source gives, keyed by each section's first step.
    public static func plan(title: String, ingredientGroups: [String?], steps: [String], stepGroups: [Int: String] = [:]) -> Plan? {
        let runs = groupRuns(ingredientGroups)
        guard runs.count >= 2, !runs.isEmpty, steps.count >= 2 else { return nil }

        // Every step a label or a section heads, the labels printed under every group left out.
        var labels: [(step: Int, words: Set<String>, opensComponent: Bool)] = []
        if !stepGroups.isEmpty {
            labels = stepGroups.sorted { $0.key < $1.key }.filter { steps.indices.contains($0.key) }.map { ($0.key, words($0.value), true) }
        } else {
            let found = steps.enumerated().compactMap { index, text in label(of: text).map { (index, $0) } }
            let counts = Dictionary(grouping: found, by: { normalized($0.1) }).mapValues(\.count)
            labels = found.filter { counts[normalized($0.1)] == 1 }.map { step, label in
                (step, words(label), label.range(of: #"^(for|to make|to prepare|make|prepare) the\b"#, options: [.regularExpression, .caseInsensitive]) != nil)
            }
        }

        // Labels to groups by the words they share, the best pairs first, ties in reading order.
        var starts: [Int: Int] = [:]
        var pairs: [(run: Int, label: Int, score: Int)] = []
        for (r, run) in runs.enumerated() {
            for (l, label) in labels.enumerated() {
                let shared = run.words.intersection(label.words)
                guard !shared.subtracting(genericWords).isEmpty else { continue }
                pairs.append((r, l, shared.count))
            }
        }
        var usedLabels = Set<Int>()
        for pair in pairs.sorted(by: { ($0.score, -$0.run, -$0.label) > ($1.score, -$1.run, -$1.label) })
        where starts[pair.run] == nil && !usedLabels.contains(pair.label) {
            starts[pair.run] = labels[pair.label].step
            usedLabels.insert(pair.label)
        }
        // As many labels as named groups, in the same order as the names that matched: paired in
        // order ("Cook the short ribs:" with "To serve").
        let named = runs.indices.filter { runs[$0].name != nil }
        if labels.count == named.count, starts.allSatisfy({ run, step in labels.firstIndex { $0.step == step } == named.firstIndex(of: run) }) {
            for (run, label) in zip(named, labels) { starts[run] = label.step }
            usedLabels = Set(labels.indices)
        }
        // A group no label names: the first step after the group before it that names its ingredient.
        for (r, run) in runs.enumerated() where starts[r] == nil && run.name != nil {
            let after = (0..<r).compactMap { starts[$0] }.max().map { $0 + 1 } ?? 0
            let before = ((r + 1)..<runs.count).compactMap { starts[$0] }.min() ?? steps.count
            let named = run.words.subtracting(genericWords)
            guard !named.isEmpty, after < before else { continue }
            if let step = (after..<before).first(where: { !words(steps[$0]).isDisjoint(with: named) }) {
                starts[r] = step
            }
        }
        // Labels left over that read as serving or as a component ("To serve:", "For the garnish:")
        // close the run before them; their steps stay with the parent. Any other ("Season with
        // salt:") is a step's own words.
        let closing = labels.indices.filter { index in
            !usedLabels.contains(index) && (!labels[index].words.isDisjoint(with: servingWords) || labels[index].opensComponent)
        }
        let boundaries = Set(starts.values).union(closing.map { labels[$0].step })

        var parts: [Part] = []
        var seen = Set<String>()
        var hasMain = false
        for (r, run) in runs.enumerated() {
            guard let name = run.name, let start = starts[r] else { continue }
            let end = boundaries.filter { $0 > start }.min() ?? steps.count
            let substance = run.words.subtracting(genericWords)
            // Serving and assembly stay with the parent, and so does the dish itself and a group that
            // carries on a component before it ("Checking the Ragu" after "Making the Ragu").
            let isServing = !run.words.isDisjoint(with: servingWords)
            // The first group the title names is the dish ("Fish" in "Fish with Salsa Verde"); a
            // later one is what it comes with.
            let isMain = !hasMain && PunchlistMatcher.similarity(componentTitle(name), title) >= 0.5
            hasMain = hasMain || isMain
            let continues = !substance.isEmpty && substance.isSubset(of: seen)
            seen.formUnion(substance)
            parts.append(Part(group: name, title: componentTitle(name), ingredients: run.indices, steps: Array(start..<end), isComponent: !isServing && !isMain && !continues, id: parts.count))
        }
        // A parent left with nothing of its own keeps the part with the most steps: the dish itself
        // ("For the Stew" beside its onions and mushrooms).
        let plan = Plan(parts: parts, ingredientCount: ingredientGroups.count, stepCount: steps.count)
        let left = plan.parent(choosing: Set(parts.indices.filter { parts[$0].isComponent }))
        if left.steps.isEmpty, left.ingredients.isEmpty,
           let main = parts.indices.filter({ parts[$0].isComponent }).max(by: { (parts[$0].steps.count, -$0) < (parts[$1].steps.count, -$1) }) {
            parts[main].isComponent = false
        }
        guard parts.contains(where: \.isComponent) else { return nil }
        return Plan(parts: parts, ingredientCount: ingredientGroups.count, stepCount: steps.count)
    }

    // MARK: - Groups and labels

    struct Run {
        var name: String?
        var indices: [Int]
        var words: Set<String>
    }

    /// Consecutive ingredient lines under one heading.
    static func groupRuns(_ groups: [String?]) -> [Run] {
        var runs: [Run] = []
        for (index, group) in groups.enumerated() {
            let name = group.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            if let last = runs.last, last.name == name {
                runs[runs.count - 1].indices.append(index)
            } else {
                runs.append(Run(name: name, indices: [index], words: name.map(words) ?? []))
            }
        }
        return runs
    }

    /// The label a step opens with: "For the piperade: Heat…" → "For the piperade", "To make the
    /// besciamella, heat…" → "To make the besciamella", "TO COMPLETE: Gently…" → "TO COMPLETE".
    static func label(of step: String) -> String? {
        let text = step.trimmingCharacters(in: .whitespaces)
        if let colon = text.firstIndex(of: ":") {
            let head = text[..<colon].trimmingCharacters(in: .whitespaces)
            let count = head.split(separator: " ").count
            if count >= 1, count <= 6, head.count <= 48, !head.contains(where: \.isNumber), head.first?.isLetter == true {
                return head
            }
        }
        if let match = text.firstMatch(of: /(?i)^((?:for|to\s+(?:make|prepare|begin|start|finish|cook|roll|assemble|serve)|before\s+(?:assembling|serving)|make|prepare)\s+the\s+[^,.:;]{2,40}),/) {
            return String(match.output.1)
        }
        return nil
    }

    /// "For the onion and jalapeño pickle" → "Onion and Jalapeño Pickle"; "BABY ARTICHOKES" → "Baby
    /// Artichokes"; "Making the Green Pasta Dough" → "Green Pasta Dough".
    public static func componentTitle(_ group: String) -> String {
        var text = group.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":")))
        text = text.replacing(/(?i)^(?:for\s+(?:the\s+)?|to\s+\w+\s+(?:the\s+)?|\w+ing\s+the\s+|make\s+(?:the\s+)?|prepare\s+(?:the\s+)?)/, with: "")
        let small: Set<String> = ["and", "or", "of", "with", "the", "a", "an", "in", "à", "la", "le", "de", "du", "for", "on"]
        let shouting = text == text.uppercased()
        let words = text.split(separator: " ").enumerated().map { index, word -> String in
            let lower = word.lowercased()
            if index > 0, small.contains(lower) { return lower }
            guard shouting || word.first?.isLowercase == true else { return String(word) }
            // "quick-pickled" → "Quick-Pickled".
            return lower.split(separator: "-", omittingEmptySubsequences: false).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "-")
        }
        return words.joined(separator: " ")
    }

    /// Words that pair a label with a group only alongside a word of substance.
    static let genericWords: Set<String> = ["mak", "prepar", "cook", "begin", "start", "finish", "complet", "assembl", "serv", "check", "roll", "first"]
    /// Words that mark a group the parent keeps by default.
    static let servingWords: Set<String> = ["serv", "assembl", "assembly", "finish", "garnish", "plat", "complet", "topp"]

    static func normalized(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0 == " " }
    }

    /// A text's words of substance, folded and stemmed so "onions" meets "onion", "rolling" "roll",
    /// "making" "make".
    static func words(_ text: String) -> Set<String> {
        let stop: Set<String> = ["for", "the", "to", "a", "an", "and", "or", "of", "with", "in", "on", "into", "it", "them", "is", "be", "until", "each", "all", "your"]
        return Set(normalized(text).split(separator: " ").map(String.init).filter { $0.count >= 3 && !stop.contains($0) }.map(stem))
    }

    static func stem(_ word: String) -> String {
        var word = word
        // The plural first, then the verb's ending: "toppings" → "topping" → "topp".
        for suffix in ["es", "s"] where word.count >= suffix.count + 3 && word.hasSuffix(suffix) && !word.hasSuffix("ss") {
            word.removeLast(suffix.count)
            break
        }
        for suffix in ["ing", "ed"] where word.count >= suffix.count + 3 && word.hasSuffix(suffix) {
            word.removeLast(suffix.count)
            break
        }
        // "rolling" → "roll" keeps its double letter; "making" → "mak", "make" → "mak".
        if word.hasSuffix("e"), word.count > 3 { word.removeLast() }
        return word
    }
}

extension ImportedRecipe {
    /// The split its groups allow, if any (`ComponentSplit.plan`).
    public var splitPlan: ComponentSplit.Plan? {
        ComponentSplit.plan(title: title, ingredientGroups: ingredients.indices.map(group(forIngredientAt:)), steps: steps.map(\.text), stepGroups: stepGroups)
    }
}
