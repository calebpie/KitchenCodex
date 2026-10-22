import Foundation

/// Reads an article off a web page that carries Article markup and no recipe (02 §4.2: the web
/// importer's second pipeline; 04 §5.1 "Import reading"). Schema.org `Article`, `NewsArticle`,
/// `BlogPosting` and their kin in the page's JSON-LD, or an `og:type` of article, name the page as
/// one; its title, author and site come from the metadata the recipe path reads; its sections are
/// the page's visible text under its own headings, in order, from the article's heading to the
/// furniture that follows it (comments, related stories, the newsletter box), and its figures the
/// content images among them, each after the section it follows, captioned from its alt text
/// (ux-notes row 130; icons, logos and images set small are left out as the recipe import's step
/// photos are); the JSON-LD's `articleBody` stands in when the text gives too little. A page that
/// holds a recipe never reaches this reader (`WebRecipeImporter.extract` asks only when no recipe
/// was found).
public enum WebReferenceReader {
    /// The article on the page, or nil when the page carries no Article markup or too little prose.
    public static func read(html: String, url: URL?) -> ImportedReference? {
        let page = HTMLPage(html: html)
        return read(page: page, metadata: PageMetadata(page: page, url: url))
    }

    static func read(page: HTMLPage, metadata: PageMetadata) -> ImportedReference? {
        let node = articleNode(in: page)
        let typed = node != nil || page.meta("og:type")?.lowercased().hasPrefix("article") == true
        guard typed else { return nil }

        var title = metadata.title
        if title.isEmpty, let headline = node.flatMap({ string($0["headline"]) ?? string($0["name"]) }) {
            title = ImportText.cleanTitle(headline, siteName: metadata.siteName, host: metadata.hostName)
        }
        let author = node.flatMap { names(of: $0["author"] ?? $0["creator"]) } ?? metadata.author
        var (sections, figures) = read(page.lines, title: title, base: metadata.sourceURL)
        var confidence = node == nil ? 0.6 : 0.8
        let characters = sections.reduce(0) { $0 + $1.body.count }
        if characters < minimumCharacters, let body = node.flatMap({ string($0["articleBody"]) }).map(ImportText.paragraphs), body.count >= minimumCharacters {
            // The text walk found little (a page built by scripts); the markup's body is whole,
            // without its headings.
            sections = body.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                .reduce(into: [ImportedReference.Section]()) { result, paragraph in
                    if result.isEmpty { result.append(ImportedReference.Section(body: paragraph)) } else { result[0].body += "\n\n" + paragraph }
                }
            figures = []
            confidence = 0.7
        }
        guard sections.reduce(0, { $0 + $1.body.count }) >= minimumCharacters, !title.isEmpty else { return nil }
        var article = ImportedReference(
            title: title,
            author: author,
            siteName: metadata.siteName ?? metadata.hostName,
            sourceURL: metadata.sourceURL,
            imageURL: metadata.imageURL,
            kind: .article,
            sections: sections,
            confidence: confidence
        )
        article.figures = figures
        return article
    }

    /// Prose under the article's title, so a shell page or a page of links is no article.
    static let minimumCharacters = 300

    // MARK: - Markup

    private static let articleTypes: Set<String> = [
        "article", "newsarticle", "blogposting", "techarticle", "scholarlyarticle", "report", "liveblogposting", "socialmediaposting", "opinionnewsarticle", "analysisnewsarticle",
    ]

    /// The first Article node in the page's JSON-LD, bare, in an array or under `@graph`.
    static func articleNode(in page: HTMLPage) -> [String: Any]? {
        for block in page.jsonLDBlocks {
            guard let json = try? JSONSerialization.jsonObject(with: Data(block.utf8), options: [.fragmentsAllowed]) else { continue }
            var found: [String: Any]?
            collect(in: json, depth: 0, into: &found)
            if let found { return found }
        }
        return nil
    }

    private static func collect(in json: Any, depth: Int, into found: inout [String: Any]?) {
        guard found == nil, depth < 10 else { return }
        if let object = json as? [String: Any] {
            if strings(object["@type"]).contains(where: { articleTypes.contains($0.lowercased()) }) {
                found = object
                return
            }
            for key in object.keys.sorted() where key != "@context" {
                collect(in: object[key]!, depth: depth + 1, into: &found)
            }
        } else if let array = json as? [Any] {
            for element in array { collect(in: element, depth: depth + 1, into: &found) }
        }
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func strings(_ value: Any?) -> [String] {
        switch value {
        case let array as [Any]: array.compactMap { string($0) }
        default: string(value).map { [$0] } ?? []
        }
    }

    /// "A. Cook", or "A. Cook and B. Baker": the author's name, a Person's, or several.
    private static func names(of value: Any?) -> String? {
        var found: [String] = []
        switch value {
        case let text as String:
            found = [ImportText.inline(text)]
        case let object as [String: Any]:
            found = string(object["name"]).map { [ImportText.inline($0)] } ?? []
        case let array as [Any]:
            found = array.compactMap { names(of: $0) }
        default:
            break
        }
        let people = found.filter { !$0.isEmpty && !$0.hasPrefix("http") }
        switch people.count {
        case 0: return nil
        case 1: return people[0]
        default: return people.dropLast().joined(separator: ", ") + " and " + people.last!
        }
    }

    // MARK: - The text

    /// Headings that end an article: what sites print after it.
    private static let stopHeadings: Set<String> = [
        "comments", "comment", "leave a comment", "leave a reply", "reviews", "ratings", "related", "related recipes",
        "related posts", "related articles", "related stories", "you may also like", "you might also like", "more recipes",
        "more from", "more stories", "more like this", "recommended", "recommended for you", "popular", "popular posts",
        "most popular", "recent posts", "latest", "trending", "tags", "tagged", "share", "share this", "print",
        "advertisement", "newsletter", "subscribe", "sign up", "about the author", "read more", "read next", "up next",
        "next", "previous", "categories", "sponsored", "explore more", "keep reading", "footer", "in this article",
    ]
    private static let noisePattern = #"newsletter|subscribe|sign up|signup|advertisement|affiliate|cookie|©|copyright|all rights reserved|privacy policy|terms of (use|service)"#

    /// The article's headed sections from its visible text: from the heading that matches the title
    /// (else the first `<h1>`, else the top), each later heading opens a section, prose lines fill
    /// the one open, and the page's furniture after the article ends it.
    static func sections(in lines: [PageLine], title: String) -> [ImportedReference.Section] {
        read(lines, title: title, base: nil).sections
    }

    /// The sections, and the figures among them: each content image before a line follows the
    /// section open when it appears, its caption its alt text (or the figure's caption line under
    /// it). An image the page repeats is kept once.
    static func read(_ lines: [PageLine], title: String, base: URL?) -> (sections: [ImportedReference.Section], figures: [ImportedReference.Figure]) {
        let titleKey = ImportText.normalizedForComparison(title)
        let start = lines.firstIndex { $0.isHeading && ImportText.normalizedForComparison($0.text) == titleKey }
            ?? lines.firstIndex { $0.headingLevel == 1 }
        var sections = [ImportedReference.Section(body: "")]
        var paragraphs: [[String]] = [[]]
        var figures: [(figure: ImportedReference.Figure, open: Int)] = []
        var seen = Set<URL>()
        for line in lines[(start.map { $0 + 1 } ?? 0)...] {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let key = ImportText.normalizedForComparison(text)
            if stopHeadings.contains(key), text.count <= 40 { break }
            for (index, source) in line.images.enumerated() {
                guard let url = ImportText.url(source, relativeTo: base), seen.insert(url).inserted else { continue }
                let alt = line.imageAlts.indices.contains(index) ? line.imageAlts[index] : ""
                figures.append((ImportedReference.Figure(url: url, caption: alt, section: sections.count - 1), sections.count - 1))
            }
            // A figure's own caption line: the caption of the figure just before it when it had none.
            if line.tag == "figcaption", let last = figures.indices.last, figures[last].figure.caption.isEmpty, !text.isEmpty {
                figures[last].figure.caption = text
            }
            guard !key.isEmpty else { continue }
            if text.count <= 140, text.lowercased().range(of: noisePattern, options: .regularExpression) != nil { continue }
            if isFurniture(text) { continue }
            if let level = line.headingLevel {
                if level <= 1, key == titleKey { continue }
                guard text.count <= 90 else { continue }
                sections.append(ImportedReference.Section(heading: heading(text), body: ""))
                paragraphs.append([])
                continue
            }
            let words = text.split(whereSeparator: \.isWhitespace).count
            // Crumbs, captions and buttons are short; a paragraph is not.
            guard words >= 4 || text.count >= 40, !["button", "label", "option", "summary", "legend", "figcaption"].contains(line.tag) else { continue }
            paragraphs[paragraphs.count - 1].append(text)
        }
        for index in sections.indices { sections[index].body = paragraphs[index].joined(separator: "\n\n") }
        // Sections with no prose go; a figure after one follows the last kept before it.
        var kept: [Int] = []
        var place: [Int: Int] = [:]
        for index in sections.indices {
            if !sections[index].body.isEmpty { kept.append(index) }
            place[index] = kept.count - 1
        }
        let placed = figures.map { entry in
            var figure = entry.figure
            figure.section = place[entry.open] ?? -1
            return figure
        }
        return (kept.map { sections[$0] }, placed)
    }

    /// The heading as a section's: no trailing colon, capitals made title case.
    static func heading(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        while result.hasSuffix(":") { result.removeLast() }
        return PageLines.titleText(result.trimmingCharacters(in: .whitespaces))
    }

    private static let months = "january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec"

    /// Dates, bylines, links written out.
    static func isFurniture(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.range(of: #"^(\#(months))\.? \d{1,2}(,? \d{4})?$"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"^\d{1,2} (\#(months))\.?( \d{4})?$"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"^(by|written by|photo(graph)?s? by|recipe by|updated|published|posted|last updated)\b"#, options: .regularExpression) != nil, text.count <= 80 { return true }
        return lower.contains("http://") || lower.contains("https://") || lower.contains("www.")
    }
}
