import Foundation

/// A supplier as a cookbook's Sources page lists it (02 Flow C step 8, 03 §3.17 Sources): the name,
/// what they carry in the book's own words, a phone number, a website and an address, and the
/// group the page prints it under.
public struct ImportedSource: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable {
        /// A shop with an address.
        case store
        /// A website and no address.
        case online
        /// A farm, dairy, fishmonger or maker that sells direct.
        case producer
    }

    public var name: String
    public var kind: Kind
    /// "equipment", "food" or "drink", as the page groups its entries; empty when it doesn't.
    public var categories: [String]
    public var carries: String
    public var phone: String?
    public var url: URL?
    public var address: String?

    public init(name: String, kind: Kind = .store, categories: [String] = [], carries: String = "", phone: String? = nil, url: URL? = nil, address: String? = nil) {
        self.name = name
        self.kind = kind
        self.categories = categories
        self.carries = carries
        self.phone = phone
        self.url = url
        self.address = address
    }
}

/// Reads a book's Sources or Resources page into its suppliers (02 Flow C step 8): a name line
/// opens an entry; the lines under it are its phone number, website and address by their shape,
/// and the rest is what they carry; a short heading between entries (Equipment · Food · Drink, or
/// a word that means one of them) groups what follows.
public enum SourcesPageReader {
    /// The page's suppliers, in the order printed. A short website or phone line the structurer
    /// set aside as noise (a URL reads with low confidence) is a contact line here.
    public static func read(_ reading: PageReading) -> [ImportedSource] {
        let blocks = reading.blocks.filter { block in
            guard block.kind != .photo, block.role != .furniture else { return false }
            return block.role != .ignore || website(in: block.text) != nil || phoneNumber(in: block.text) != nil
        }
        return read(lines: blocks.flatMap { $0.lines.map(\.text) })
    }

    /// The suppliers in lines of text, as the page prints them top to bottom.
    public static func read(lines: [String]) -> [ImportedSource] {
        var sources: [ImportedSource] = []
        var category: String?
        var current: ImportedSource?
        var currentHasDetails = false

        func finish() {
            if var source = current {
                source.carries = source.carries.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;")))
                source.kind = kind(of: source)
                sources.append(source)
            }
            current = nil
            currentHasDetails = false
        }

        let texts = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0.contains(where: { $0.isLetter || $0.isNumber }) }
        for (index, text) in texts.enumerated() {
            let lower = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if ["sources", "resources", "suppliers", "source guide", "where to buy", "mail-order sources", "mail order sources"].contains(lower) { continue }
            // A heading names a group and is followed by a name or the group's introduction; a
            // shop called "Sakura Pantry" is followed by its details. "For Equipment" is a heading.
            if let group = categoryHeading(text),
               lower.hasPrefix("for ") || !isName(text) || index + 1 >= texts.count || isName(texts[index + 1]) || categoryHeading(texts[index + 1]) != nil
                || (phoneNumber(in: texts[index + 1]) == nil && website(in: texts[index + 1]) == nil && !isAddress(texts[index + 1])) {
                finish()
                category = group
                continue
            }
            let phone = phoneNumber(in: text)
            let site = website(in: text)
            if phone != nil || site != nil {
                if current == nil { current = ImportedSource(name: "", categories: category.map { [$0] } ?? []) }
                if let phone, current?.phone == nil { current?.phone = phone }
                if let site, current?.url == nil { current?.url = site }
                currentHasDetails = true
                continue
            }
            if isAddress(text) {
                var open = current ?? ImportedSource(name: "", categories: category.map { [$0] } ?? [])
                open.address = open.address.map { "\($0), \(text)" } ?? text
                current = open
                currentHasDetails = true
                continue
            }
            // A "Contact:" line names a person, not the supplier.
            if lower.hasPrefix("contact") { continue }
            // A name set over two lines ("CULINARY INSTITUTE OF" / "AMERICA AT GREYSTONE").
            if isName(text), let open = current, !open.name.isEmpty, !currentHasDetails, open.carries.isEmpty {
                current?.name = open.name + " " + text
                continue
            }
            if isName(text), current == nil || currentHasDetails || !current!.carries.isEmpty || current!.name.isEmpty {
                if let open = current, open.name.isEmpty {
                    // Details printed above the name (a photo's caption order): the name finishes them.
                    current?.name = text
                    continue
                }
                finish()
                current = ImportedSource(name: text, categories: category.map { [$0] } ?? [])
                continue
            }
            // What they carry, in the book's words.
            if var open = current {
                open.carries = open.carries.isEmpty ? text : open.carries + " " + text
                current = open
            }
        }
        finish()
        return sources.filter { !$0.name.isEmpty && ($0.phone != nil || $0.url != nil || $0.address != nil || !$0.carries.isEmpty) }
    }

    // MARK: - Lines

    private static let equipmentWords: Set<String> = ["equipment", "kitchenware", "cookware", "tools", "tableware", "supplies", "hardware", "knives", "bakeware", "utensils", "appliances"]
    private static let drinkWords: Set<String> = ["drink", "drinks", "wine", "wines", "beverages", "beverage", "spirits", "sake", "beer", "tea", "teas", "coffee", "bar"]
    private static let foodWords: Set<String> = ["food", "foods", "ingredients", "pantry", "produce", "meat", "meats", "fish", "seafood", "cheese", "cheeses", "spices", "groceries", "grocery", "specialty", "specialties", "bakery", "chocolate", "charcuterie", "condiments", "grains", "flours", "dairy", "poultry", "vegetables", "fruit", "fruits", "herbs"]

    /// "EQUIPMENT", "Food", "Drink", "Japanese Ingredients": the group the lines after it belong to.
    static func categoryHeading(_ text: String) -> String? {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        guard (1...4).contains(words.count), !text.contains(where: \.isNumber), !text.contains(","), !text.contains(":") || text.hasSuffix(":") else { return nil }
        guard text.count <= 40 else { return nil }
        if words.contains(where: equipmentWords.contains) { return "equipment" }
        if words.contains(where: drinkWords.contains) { return "drink" }
        if words.contains(where: foodWords.contains) { return "food" }
        return nil
    }

    /// A supplier's name: a short line in title case or capitals, no digits, no sentence.
    static func isName(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard (1...7).contains(words.count), text.count <= 50, !text.contains(where: \.isNumber) else { return false }
        guard let first = text.first, first.isUppercase else { return false }
        let lower = text.lowercased()
        guard !(text.last.map { ".,;:".contains($0) } ?? false) || ["inc.", "co.", "ltd.", "llc.", "corp."].contains(where: lower.hasSuffix) else { return false }
        let letters = text.filter(\.isLetter)
        if letters.count >= 3, letters.allSatisfy({ !$0.isLowercase }) { return true }
        let significant = words.filter { $0.filter(\.isLetter).count >= 3 && !["and", "the", "for", "of", "de", "des", "du", "la", "le", "les", "with", "from"].contains($0.lowercased()) }
        guard !significant.isEmpty else { return false }
        let capitalised = significant.count { $0.first?.isUppercase == true }
        return Double(capitalised) >= Double(significant.count) * 0.6
    }

    static func phoneNumber(in text: String) -> String? {
        if let match = text.firstMatch(of: /(\+?\d{1,3}[\s.\-]?)?\(?\d{3}\)?[\s.\-]\d{3}[\s.\-]\d{4}\b/) {
            return String(match.output.0).trimmingCharacters(in: .whitespaces)
        }
        // A number spelled in letters, "866-PANSHOP (72674671)", "1-800-5-KNIVES".
        if let match = text.firstMatch(of: /\b(?:1-)?\d{3}-(?:\d-)?[A-Z]{4,}[A-Z0-9]*(?:\s*\([\d\-]{7,}\))?/) {
            return String(match.output).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func website(in text: String) -> URL? {
        guard let match = text.firstMatch(of: /(?i)\b(https?:\/\/\S+|www\.\S+|[a-z0-9][a-z0-9\-]*(?:\.[a-z0-9\-]+)*\.(?:com|net|org|co\.uk|co|ca|fr|it|jp|de|edu|io|shop|store)\b\S*)/) else { return nil }
        var address = String(match.output.1).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)"))
        if !address.lowercased().hasPrefix("http") { address = "https://" + address }
        return URL(string: address)
    }

    /// "123 Hudson Street", "Brooklyn, NY 11201", "P.O. Box 12", "Suite 4": a line of an address.
    static func isAddress(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.range(of: #"^\d{1,6}[a-z]?\s+[a-z]"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"\b(street|st\.|avenue|ave\.|road|rd\.|lane|ln\.|drive|dr\.|boulevard|blvd|place|pl\.|suite|ste\.|floor|fl\.|p\.?o\.? box|box \d|highway|hwy|route|rte|market|plaza|square|court|way)\b"#, options: .regularExpression) != nil, text.contains(where: \.isNumber) || lower.hasPrefix("p") { return true }
        return text.range(of: #"[A-Za-z .'’]+,\s*[A-Z]{2}\s+\d{5}(-\d{4})?"#, options: .regularExpression) != nil
    }

    /// A farm, dairy or maker sells direct; a shop has an address; a site alone is online.
    static func kind(of source: ImportedSource) -> ImportedSource.Kind {
        let words = (source.name + " " + source.carries).lowercased()
        if words.range(of: #"\b(farm|farms|dairy|ranch|orchard|creamery|fishmonger|butcher|bakery|mill|apiary|vineyard|winery|brewery|distillery|smokehouse|growers?|producers?)\b"#, options: .regularExpression) != nil { return .producer }
        if source.address != nil { return .store }
        if source.url != nil { return .online }
        return .store
    }
}
