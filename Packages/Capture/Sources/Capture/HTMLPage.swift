import Foundation

/// One line of visible text, with the block element it came from.
struct PageLine: Sendable, Equatable {
    var text: String
    /// The innermost block element holding the text ("li", "p", "h2", "div", "button"…).
    var tag: String
    /// 1…6 when the line sits inside a heading element.
    var headingLevel: Int?
    /// Identifies the `ul`/`ol` the line belongs to, if any.
    var listID: Int?

    var isHeading: Bool { headingLevel != nil }
}

/// A microdata property (`itemprop`) and its value.
struct MicrodataProperty: Sendable, Equatable {
    var name: String
    /// The `content`, `src` or `href` attribute when present, otherwise the element's text with
    /// block boundaries as newlines.
    var value: String
    /// The `itemtype` of the nearest enclosing `itemscope`, if any.
    var scopeType: String?
}

/// What the importer needs from a page: its metadata, structured data blocks and visible text.
///
/// Visible text follows what a reader sees: scripts, styles, `<nav>`, `<footer>`, SVG and anything
/// marked `hidden`, `aria-hidden` or `display: none` are skipped. Block elements and `<br>` end
/// lines; adjacent inline elements get a space between them.
struct HTMLPage: Sendable {
    var title: String?
    /// `<meta>` values keyed by lowercased `property` or `name` ("og:title", "author"…). First wins.
    var metas: [String: String] = [:]
    var canonicalURL: String?
    var jsonLDBlocks: [String] = []
    var lines: [PageLine] = []
    var microdata: [MicrodataProperty] = []

    init(html: String) {
        var builder = Builder()
        var tokenizer = HTMLTokenizer(html)
        while let token = tokenizer.next() {
            builder.consume(token)
        }
        builder.finish()
        title = builder.title
        metas = builder.metas
        canonicalURL = builder.canonicalURL
        jsonLDBlocks = builder.jsonLDBlocks
        lines = builder.lines
        microdata = builder.microdata
    }

    func meta(_ keys: String...) -> String? {
        for key in keys {
            if let value = metas[key]?.collapsingWhitespace, !value.isEmpty { return value }
        }
        return nil
    }
}

// MARK: - Building

private struct Builder {
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
        "source", "track", "wbr", "keygen",
    ]
    static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "button", "caption", "center", "dd",
        "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer",
        "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "html", "legend", "li",
        "main", "menu", "nav", "ol", "option", "p", "pre", "section", "summary", "table", "tbody",
        "tfoot", "thead", "tr", "ul",
    ]
    /// Elements whose content a reader never sees as recipe text.
    static let skippedElements: Set<String> = [
        "nav", "footer", "svg", "math", "template", "iframe", "noscript", "select", "object",
        "video", "audio", "canvas", "map", "head",
    ]
    static let hiddenClasses: Set<String> = [
        "sr-only", "visually-hidden", "visuallyhidden", "screen-reader-text", "screenreader-only",
        "hidden", "hide", "d-none", "is-hidden",
    ]
    /// Elements whose open tag implicitly closes an open `<p>`.
    static let closesParagraph: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "div", "dl", "fieldset", "figcaption",
        "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "main",
        "menu", "nav", "ol", "p", "pre", "section", "table", "ul",
    ]

    struct OpenElement {
        var name: String
        var isSkipped: Bool
        var headingLevel: Int?
        var listID: Int?
        var itemScopeType: String?
        var isJSONLDScript = false
        var captureIDs: [Int] = []
    }

    struct Capture {
        var name: String
        var scopeType: String?
        var text = ""
        /// Characters of the current line that precede the element, so they are left out.
        var startOffset = 0

        func pending(_ line: String) -> String {
            String(line.dropFirst(startOffset))
        }
    }

    var title: String?
    var metas: [String: String] = [:]
    var canonicalURL: String?
    var jsonLDBlocks: [String] = []
    var lines: [PageLine] = []
    var microdata: [MicrodataProperty] = []

    private var stack: [OpenElement] = []
    private var skipDepth = 0
    private var currentLine = ""
    private var currentTag = "body"
    private var currentHeading: Int?
    private var currentList: Int?
    private var lastTokenWasInlineEnd = false
    private var nextListID = 0
    private var activeCaptures: [Int: Capture] = [:]
    private var nextCaptureID = 0

    mutating func consume(_ token: HTMLTokenizer.Token) {
        switch token {
        case let .startTag(name, attributes, selfClosing):
            open(name, attributes: attributes, selfClosing: selfClosing)
        case let .endTag(name):
            close(name)
        case let .text(text):
            appendText(text)
        case let .rawText(element, content):
            handleRawText(element: element, content: content)
        }
    }

    mutating func finish() {
        flushLine()
        while !stack.isEmpty { popElement() }
    }

    // MARK: Tags

    private mutating func open(_ name: String, attributes: [String: String], selfClosing: Bool) {
        // Head metadata is read whether or not the element is "visible".
        switch name {
        case "meta":
            if let key = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"])?.lowercased(),
               let content = attributes["content"], metas[key] == nil {
                metas[key] = content
            }
        case "link":
            if attributes["rel"]?.lowercased().split(separator: " ").contains("canonical") == true {
                canonicalURL = canonicalURL ?? attributes["href"]
            }
        case "body":
            // Anything left open in <head> (a stray <noscript>) must not hide the body.
            while let index = stack.lastIndex(where: { $0.name == "head" || $0.isSkipped }) {
                while stack.count > index { popElement() }
            }
        default:
            break
        }

        let isVoid = Self.voidElements.contains(name) || selfClosing

        // Implied end tags, so a stray <li> or <p> doesn't nest forever.
        if name == "li" { closeOpen("li", stoppingAt: ["ul", "ol", "menu"]) }
        if name == "dt" || name == "dd" { closeOpen("dt", stoppingAt: ["dl"]); closeOpen("dd", stoppingAt: ["dl"]) }
        if name == "tr" { closeOpen("tr", stoppingAt: ["table", "tbody", "thead", "tfoot"]) }
        if name == "td" || name == "th" { closeOpen("td", stoppingAt: ["tr"]); closeOpen("th", stoppingAt: ["tr"]) }
        if name == "option" { closeOpen("option", stoppingAt: ["select", "datalist"]) }
        if Self.closesParagraph.contains(name) { closeOpen("p", stoppingAt: ["button", "li", "td", "th", "div", "section", "article"]) }

        let hidden = Self.isHidden(attributes)
        let skipped = skipDepth > 0 || hidden || Self.skippedElements.contains(name)
        let isBlock = Self.blockElements.contains(name)

        if !skipped {
            if name == "br" {
                flushLine()
            } else if isBlock {
                flushLine()
            } else if name == "td" || name == "th" || name == "img" {
                separateWithSpace()
            } else if lastTokenWasInlineEnd {
                // "</span><span>": siblings the browser would typically lay out apart.
                separateWithSpace()
            }
        }
        lastTokenWasInlineEnd = false

        // Microdata.
        var captureIDs: [Int] = []
        if !skipped, let itemprop = attributes["itemprop"] {
            let scope = currentItemScope
            let direct = attributes["content"] ?? (name == "img" ? attributes["src"] : nil)
                ?? (["a", "link"].contains(name) ? attributes["href"] : nil)
                ?? (name == "time" ? attributes["datetime"] : nil)
            for property in itemprop.split(separator: " ").map(String.init) {
                if let direct {
                    microdata.append(MicrodataProperty(name: property, value: direct, scopeType: scope))
                } else if !isVoid {
                    nextCaptureID += 1
                    activeCaptures[nextCaptureID] = Capture(name: property, scopeType: scope, startOffset: currentLine.count)
                    captureIDs.append(nextCaptureID)
                }
            }
        }

        guard !isVoid else { return }

        var element = OpenElement(name: name, isSkipped: skipped)
        if let level = Self.headingLevel(name) {
            element.headingLevel = level
        }
        if name == "ul" || name == "ol" || name == "menu" {
            nextListID += 1
            element.listID = nextListID
        }
        if attributes["itemscope"] != nil {
            element.itemScopeType = attributes["itemtype"] ?? ""
        }
        element.isJSONLDScript = name == "script" && attributes["type"]?.lowercased().contains("ld+json") == true
        element.captureIDs = captureIDs
        stack.append(element)
        if skipped { skipDepth += 1 }

        if isBlock && !skipped {
            currentTag = name
            currentHeading = currentHeadingLevel
            currentList = currentListID
        }
    }

    private mutating func close(_ name: String) {
        guard let index = stack.lastIndex(where: { $0.name == name }) else { return }
        // Don't let a stray end tag deep in a list unwind the whole document.
        guard stack.count - index <= 24 else { return }
        let isBlock = Self.blockElements.contains(name)
        while stack.count > index { popElement() }
        if isBlock {
            flushLine()
            // The text that follows belongs to the enclosing block.
            if let block = stack.last(where: { Self.blockElements.contains($0.name) }) {
                currentTag = block.name
            }
            currentHeading = currentHeadingLevel
            currentList = currentListID
            lastTokenWasInlineEnd = false
        } else {
            lastTokenWasInlineEnd = skipDepth == 0
        }
    }

    private mutating func popElement() {
        guard let element = stack.popLast() else { return }
        if element.isSkipped { skipDepth -= 1 }
        for id in element.captureIDs {
            guard let capture = activeCaptures.removeValue(forKey: id) else { continue }
            let value = (capture.text + capture.pending(currentLine))
                .components(separatedBy: "\n")
                .map(\.collapsingWhitespace)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            microdata.append(MicrodataProperty(name: capture.name, value: value, scopeType: capture.scopeType))
        }
    }

    private mutating func closeOpen(_ name: String, stoppingAt boundaries: Set<String>) {
        guard let index = stack.lastIndex(where: { $0.name == name || boundaries.contains($0.name) }),
              stack[index].name == name else { return }
        while stack.count > index { popElement() }
        flushLine()
    }

    // MARK: Text

    private mutating func appendText(_ text: String) {
        lastTokenWasInlineEnd = false
        guard skipDepth == 0 else { return }
        currentLine += text
    }

    private mutating func separateWithSpace() {
        guard let last = currentLine.last, !last.isWhitespace else { return }
        currentLine += " "
    }

    private mutating func flushLine() {
        // Open microdata captures take the line as it ends, so they see the same text as `lines`.
        for id in activeCaptures.keys {
            activeCaptures[id]!.text += activeCaptures[id]!.pending(currentLine) + "\n"
            activeCaptures[id]!.startOffset = 0
        }
        let text = currentLine.collapsingWhitespace
        currentLine = ""
        guard !text.isEmpty else { return }
        lines.append(PageLine(text: text, tag: currentTag, headingLevel: currentHeading, listID: currentList))
    }

    private mutating func handleRawText(element: String, content: String) {
        switch element {
        case "title":
            if title == nil { title = HTMLEntities.decode(content).collapsingWhitespace }
        case "script":
            // The tokenizer only reports the content; the start tag told us the type.
            if let open = stack.last, open.name == "script", open.isJSONLDScript {
                jsonLDBlocks.append(content)
            }
        default:
            break
        }
    }

    // MARK: Context

    private var currentHeadingLevel: Int? {
        stack.last(where: { $0.headingLevel != nil })?.headingLevel
    }

    private var currentListID: Int? {
        stack.last(where: { $0.listID != nil })?.listID
    }

    private var currentItemScope: String? {
        stack.last(where: { $0.itemScopeType != nil })?.itemScopeType
    }

    private static func headingLevel(_ name: String) -> Int? {
        guard name.count == 2, name.first == "h", let level = Int(String(name.last!)), (1...6).contains(level) else { return nil }
        return level
    }

    private static func isHidden(_ attributes: [String: String]) -> Bool {
        if attributes["hidden"] != nil { return true }
        if attributes["aria-hidden"]?.lowercased() == "true" { return true }
        if let style = attributes["style"]?.lowercased().replacingOccurrences(of: " ", with: ""),
           style.contains("display:none") || style.contains("visibility:hidden") {
            return true
        }
        if let classes = attributes["class"]?.lowercased().split(whereSeparator: \.isWhitespace),
           classes.contains(where: { hiddenClasses.contains(String($0)) }) {
            return true
        }
        return false
    }
}

extension String {
    /// Whitespace runs (including non-breaking and zero-width spaces) as single spaces, trimmed.
    var collapsingWhitespace: String {
        var result = ""
        result.reserveCapacity(utf8.count)
        var pendingSpace = false
        for scalar in unicodeScalars {
            switch scalar {
            case "\u{200B}", "\u{00AD}", "\u{FEFF}", "\u{200C}", "\u{200D}", "\u{2060}":
                continue
            default:
                if scalar.properties.isWhitespace {
                    pendingSpace = !result.isEmpty
                } else {
                    if pendingSpace {
                        result.unicodeScalars.append(" ")
                        pendingSpace = false
                    }
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}
