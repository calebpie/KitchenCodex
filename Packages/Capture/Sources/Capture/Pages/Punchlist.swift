import Foundation

/// The course a contents chapter's title suggests (ux-notes row 73): its first word that names a
/// course, so "Soups & Salads" is Soup and "Fish and Shellfish" is Main. Nil when no word does
/// ("Grains", "Fry"); the cook confirms or changes it per chapter in the session. The names are
/// the library's standard courses.
public enum ChapterCourse {
    static let words: [String: String] = [
        "salad": "Salad", "salads": "Salad",
        "soup": "Soup", "soups": "Soup", "stew": "Soup", "stews": "Soup", "broths": "Soup",
        "starter": "Starter", "starters": "Starter", "appetizer": "Starter", "appetizers": "Starter",
        "antipasti": "Starter", "hors": "Starter", "small": "Starter",
        "side": "Side", "sides": "Side", "vegetable": "Side", "vegetables": "Side", "accompaniments": "Side",
        "main": "Main", "mains": "Main", "entrees": "Main", "meat": "Main", "meats": "Main", "fish": "Main",
        "seafood": "Main", "shellfish": "Main", "poultry": "Main", "birds": "Main", "chicken": "Main",
        "beef": "Main", "pork": "Main", "lamb": "Main", "game": "Main", "pasta": "Main", "pastas": "Main",
        "pizza": "Main", "pizzas": "Main",
        "dessert": "Dessert", "desserts": "Dessert", "sweets": "Dessert", "sweet": "Dessert",
        "puddings": "Dessert", "cakes": "Dessert", "tarts": "Dessert", "pastry": "Dessert", "pastries": "Dessert",
        "bread": "Bread", "breads": "Bread",
        "sauce": "Sauce", "sauces": "Sauce", "condiments": "Sauce", "condiment": "Sauce", "basics": "Sauce",
        "basic": "Sauce", "dressings": "Sauce", "pickles": "Sauce",
        "drink": "Drink", "drinks": "Drink", "cocktails": "Drink", "beverages": "Drink",
        "breakfast": "Breakfast", "brunch": "Breakfast",
        "snack": "Snack", "snacks": "Snack",
    ]

    public static func course(forChapter title: String) -> String? {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
        let tokens = folded.split { !$0.isLetter }.map(String.init)
        for (index, token) in tokens.enumerated() {
            // "Main courses" and "First courses": the first word decides.
            if token == "first", tokens.dropFirst(index + 1).first.map({ $0.hasPrefix("course") }) == true { return "Starter" }
            if token == "small", tokens.dropFirst(index + 1).first != "plates" { continue }
            if token == "hors", tokens.dropFirst(index + 1).first.map({ $0.hasPrefix("d") }) != true { continue }
            if let course = words[token] { return course }
        }
        return nil
    }
}

/// Keeps a book's punchlist in step with its scans (02 Flow C step 4, 03 §3.8): each recipe read
/// off a capture is matched to its entry by the page number read off the page, then by title, and
/// the current item moves on to the next entry not yet captured.
public enum PunchlistMatcher {
    /// One punchlist entry, in the list's order.
    public struct Entry: Sendable, Equatable {
        public var title: String
        public var page: Int?
        public var isCaptured: Bool

        public init(title: String, page: Int? = nil, isCaptured: Bool = false) {
            self.title = title
            self.page = page
            self.isCaptured = isCaptured
        }
    }

    /// The entry each recipe on a capture is, by index into `entries`, or nil for a recipe the list
    /// doesn't hold. `titles` are the recipes in reading order and `pages` the page numbers read
    /// off the capture (two for a stitched spread). With a page number, the entries listed at that
    /// page (or a page either side) are matched by title, a page's recipes taking its entries in
    /// order when their titles don't tell; with none, the first recipe is the current item and the
    /// rest are found by title.
    public static func match(titles: [String], pages: [Int], entries: [Entry], current: Int?) -> [Int?] {
        var taken = Set<Int>()
        var result = [Int?](repeating: nil, count: titles.count)
        if !pages.isEmpty {
            // Every pairing of recipe and entry near the page, best first.
            var pairs: [(recipe: Int, entry: Int, score: Double)] = []
            for (recipe, title) in titles.enumerated() {
                for (entry, item) in entries.enumerated() {
                    guard let page = item.page else { continue }
                    let distance = pages.map { abs($0 - page) }.min() ?? .max
                    guard distance <= 2 else { continue }
                    let pageScore = distance == 0 ? 2.0 : (distance == 1 ? 1.2 : 0.8)
                    let similarity = Self.similarity(title, item.title)
                    // A neighbouring page's entry needs its title to agree.
                    guard distance == 0 || similarity >= 0.5 else { continue }
                    pairs.append((recipe, entry, pageScore + similarity + (item.isCaptured ? 0 : 0.15)))
                }
            }
            for pair in pairs.sorted(by: { $0.score > $1.score }) where result[pair.recipe] == nil && !taken.contains(pair.entry) {
                // Two recipes on one page with titles that don't tell: in reading order.
                let rivals = pairs.filter { $0.entry == pair.entry && $0.recipe != pair.recipe && result[$0.recipe] == nil }
                if let rival = rivals.first, abs(rival.score - pair.score) < 0.05, rival.recipe < pair.recipe { continue }
                result[pair.recipe] = pair.entry
                taken.insert(pair.entry)
            }
            // Ties left over: the page's remaining entries in order.
            let left = entries.indices.filter { !taken.contains($0) && entries[$0].page.map(pages.contains) == true }
            for (recipe, entry) in zip(result.indices.filter { result[$0] == nil }, left) {
                result[recipe] = entry
                taken.insert(entry)
            }
        } else if let current, entries.indices.contains(current), let first = titles.indices.first {
            let elsewhere = bestTitle(titles[first], in: entries, excluding: [current], minimum: 0.75)
            if let elsewhere, similarity(titles[first], entries[current].title) < 0.3, !titles[first].isEmpty {
                result[first] = elsewhere
            } else {
                result[first] = current
            }
            taken.insert(result[first]!)
        }
        // Any recipe still without an entry: the best title anywhere on the list.
        for index in result.indices where result[index] == nil && !titles[index].isEmpty {
            if let entry = bestTitle(titles[index], in: entries, excluding: taken, minimum: 0.6) {
                result[index] = entry
                taken.insert(entry)
            }
        }
        return result
    }

    /// The next entry not yet captured after `index` in the list's order, wrapping to the top; nil
    /// once every entry is captured.
    public static func next(after index: Int?, in entries: [Entry]) -> Int? {
        let start = (index ?? -1) + 1
        let order = Array(entries.indices.dropFirst(min(start, entries.count))) + Array(entries.indices.prefix(min(start, entries.count)))
        return order.first { !entries[$0].isCaptured }
    }

    /// How alike two titles are, 0…1: the share of their words in common, without case, accents,
    /// small words or punctuation, a word the recognizer slipped on one letter still counting.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let first = words(a), second = words(b)
        guard !first.isEmpty, !second.isEmpty else { return 0 }
        var unmatched = second
        var common = 0
        for word in first {
            if let index = unmatched.firstIndex(where: { alike(word, $0) }) {
                common += 1
                unmatched.remove(at: index)
            }
        }
        return 2 * Double(common) / Double(first.count + second.count)
    }

    static func bestTitle(_ title: String, in entries: [Entry], excluding: Set<Int>, minimum: Double) -> Int? {
        let scored = entries.indices.filter { !excluding.contains($0) }.map { ($0, similarity(title, entries[$0].title) + (entries[$0].isCaptured ? 0 : 0.01)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= minimum else { return nil }
        return best.0
    }

    static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
        let small: Set<String> = ["a", "an", "and", "the", "with", "of", "on", "in", "or", "for", "de", "la", "le", "au", "a", "y", "en"]
        return folded.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !small.contains($0) }
    }

    /// The same word, or one letter apart in words of five letters or more.
    static func alike(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 5, b.count >= 5, abs(a.count - b.count) <= 1 else { return false }
        return editDistance(Array(a), Array(b)) <= 1
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var row = [i + 1]
            for (j, y) in b.enumerated() {
                row.append(min(previous[j + 1] + 1, row[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = row
        }
        return previous[b.count]
    }
}
