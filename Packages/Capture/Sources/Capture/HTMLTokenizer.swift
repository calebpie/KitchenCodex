import Foundation

/// A forgiving HTML tokenizer: just enough to read saved and fetched recipe pages without WebKit.
///
/// Works on UTF-8 bytes for speed (pages run to a megabyte). Script, style, title and textarea
/// contents come back whole as `rawText`; comments, doctypes and processing instructions are skipped.
/// Entities are decoded in text and attribute values.
struct HTMLTokenizer {
    enum Token: Equatable {
        case startTag(name: String, attributes: [String: String], selfClosing: Bool)
        case endTag(name: String)
        case text(String)
        /// The undecoded contents of a raw-text element such as `<script>` or `<style>`.
        case rawText(element: String, content: String)
    }

    /// Elements whose contents are not markup.
    static let rawTextElements: Set<String> = ["script", "style", "title", "textarea", "xmp", "plaintext"]

    private let bytes: [UInt8]
    private var index = 0
    private var pendingRawTextElement: String?

    init(_ html: String) {
        bytes = Array(html.utf8)
    }

    mutating func next() -> Token? {
        if let element = pendingRawTextElement {
            pendingRawTextElement = nil
            let end = find(closingTagOf: element, from: index) ?? bytes.count
            let content = String(decoding: bytes[index..<end], as: UTF8.self)
            index = end
            return .rawText(element: element, content: content)
        }

        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "<") {
                let before = index
                if let token = readMarkup() { return token }
                // A skipped comment or doctype: look again from where it ended, which may be more markup.
                if index == before { index += 1 }
                continue
            }
            // Text runs to the next "<".
            let start = index
            index += 1
            while index < bytes.count, bytes[index] != UInt8(ascii: "<") { index += 1 }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            return .text(HTMLEntities.decode(text))
        }
        return nil
    }

    // MARK: - Markup

    /// Reads the markup at `index` (which holds "<"). Returns nil for skipped constructs (comments,
    /// doctypes) with `index` moved past them, or for a stray "<" with `index` left on it.
    private mutating func readMarkup() -> Token? {
        let next = peek(index + 1)
        switch next {
        case UInt8(ascii: "!"):
            if matches("<!--", at: index) {
                index = (find("-->", from: index + 4).map { $0 + 3 }) ?? bytes.count
            } else if matches("<![CDATA[", at: index) {
                let start = index + 9
                let end = find("]]>", from: start) ?? bytes.count
                index = min(end + 3, bytes.count)
                return .text(String(decoding: bytes[start..<end], as: UTF8.self))
            } else {
                skipPast(UInt8(ascii: ">"))
            }
            return nil
        case UInt8(ascii: "?"):
            skipPast(UInt8(ascii: ">"))
            return nil
        case UInt8(ascii: "/"):
            var cursor = index + 2
            let name = readName(&cursor)
            guard !name.isEmpty else {
                skipPast(UInt8(ascii: ">"))
                return nil
            }
            index = cursor
            skipPast(UInt8(ascii: ">"))
            return .endTag(name: name)
        case let byte? where isASCIILetter(byte):
            return readStartTag()
        default:
            // A literal "<", as in "a < b". Let the text reader take it.
            index += 1
            let start = index - 1
            while index < bytes.count, bytes[index] != UInt8(ascii: "<") { index += 1 }
            return .text(HTMLEntities.decode(String(decoding: bytes[start..<index], as: UTF8.self)))
        }
    }

    private mutating func readStartTag() -> Token {
        var cursor = index + 1
        let name = readName(&cursor)
        var attributes: [String: String] = [:]
        var selfClosing = false

        while cursor < bytes.count {
            skipWhitespace(&cursor)
            guard cursor < bytes.count else { break }
            let byte = bytes[cursor]
            if byte == UInt8(ascii: ">") {
                cursor += 1
                break
            }
            if byte == UInt8(ascii: "/") {
                if peek(cursor + 1) == UInt8(ascii: ">") {
                    selfClosing = true
                    cursor += 2
                    break
                }
                cursor += 1
                continue
            }
            // Attribute name.
            let nameStart = cursor
            while cursor < bytes.count, !isWhitespace(bytes[cursor]),
                  bytes[cursor] != UInt8(ascii: "="), bytes[cursor] != UInt8(ascii: ">"),
                  !(bytes[cursor] == UInt8(ascii: "/") && peek(cursor + 1) == UInt8(ascii: ">")) {
                cursor += 1
            }
            if cursor == nameStart {
                cursor += 1
                continue
            }
            let attributeName = String(decoding: bytes[nameStart..<cursor], as: UTF8.self).lowercased()
            skipWhitespace(&cursor)
            var value = ""
            if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "=") {
                cursor += 1
                skipWhitespace(&cursor)
                if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "\"") || bytes[cursor] == UInt8(ascii: "'") {
                    let quote = bytes[cursor]
                    let valueStart = cursor + 1
                    var valueEnd = valueStart
                    while valueEnd < bytes.count, bytes[valueEnd] != quote { valueEnd += 1 }
                    value = String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
                    cursor = min(valueEnd + 1, bytes.count)
                } else {
                    let valueStart = cursor
                    while cursor < bytes.count, !isWhitespace(bytes[cursor]), bytes[cursor] != UInt8(ascii: ">") { cursor += 1 }
                    value = String(decoding: bytes[valueStart..<cursor], as: UTF8.self)
                }
            }
            if attributes[attributeName] == nil {
                attributes[attributeName] = HTMLEntities.decode(value)
            }
        }
        index = cursor
        if !selfClosing, Self.rawTextElements.contains(name) {
            pendingRawTextElement = name
        }
        return .startTag(name: name, attributes: attributes, selfClosing: selfClosing)
    }

    // MARK: - Byte helpers

    private func peek(_ position: Int) -> UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    private func isASCIILetter(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
    }

    private func skipWhitespace(_ cursor: inout Int) {
        while cursor < bytes.count, isWhitespace(bytes[cursor]) { cursor += 1 }
    }

    private mutating func skipPast(_ target: UInt8) {
        while index < bytes.count, bytes[index] != target { index += 1 }
        index = min(index + 1, bytes.count)
    }

    /// Reads a tag name (letters, digits, "-", ":", "_"), lowercased.
    private func readName(_ cursor: inout Int) -> String {
        let start = cursor
        while cursor < bytes.count {
            let byte = bytes[cursor]
            let isNameByte = isASCIILetter(byte) || (byte >= 0x30 && byte <= 0x39)
                || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ":") || byte == UInt8(ascii: "_")
            guard isNameByte else { break }
            cursor += 1
        }
        return String(decoding: bytes[start..<cursor], as: UTF8.self).lowercased()
    }

    private func matches(_ literal: String, at position: Int) -> Bool {
        let pattern = Array(literal.utf8)
        guard position + pattern.count <= bytes.count else { return false }
        for offset in 0..<pattern.count where bytes[position + offset] != pattern[offset] {
            return false
        }
        return true
    }

    private func find(_ literal: String, from position: Int) -> Int? {
        let pattern = Array(literal.utf8)
        guard let first = pattern.first, position < bytes.count else { return nil }
        var cursor = position
        while cursor + pattern.count <= bytes.count {
            if bytes[cursor] == first, matches(literal, at: cursor) { return cursor }
            cursor += 1
        }
        return nil
    }

    /// The position of `</element` (any case) at or after `position`.
    private func find(closingTagOf element: String, from position: Int) -> Int? {
        let name = Array(element.utf8)
        var cursor = position
        while cursor + name.count + 2 <= bytes.count {
            if bytes[cursor] == UInt8(ascii: "<"), bytes[cursor + 1] == UInt8(ascii: "/") {
                var matched = true
                for offset in 0..<name.count {
                    let byte = bytes[cursor + 2 + offset] | 0x20 // ASCII lowercase
                    if byte != name[offset] {
                        matched = false
                        break
                    }
                }
                if matched { return cursor }
            }
            cursor += 1
        }
        return nil
    }
}

/// HTML character references: numeric ones and the named ones recipe pages actually use.
enum HTMLEntities {
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var cursor = text.startIndex
        while let ampersand = text[cursor...].firstIndex(of: "&") {
            result += text[cursor..<ampersand]
            let afterAmpersand = text.index(after: ampersand)
            // Entities are short; look at most 32 characters ahead for the semicolon.
            let limit = text.index(afterAmpersand, offsetBy: 32, limitedBy: text.endIndex) ?? text.endIndex
            if let semicolon = text[afterAmpersand..<limit].firstIndex(of: ";"),
               let decoded = decodeReference(text[afterAmpersand..<semicolon]) {
                result += decoded
                cursor = text.index(after: semicolon)
            } else {
                result.append("&")
                cursor = afterAmpersand
            }
        }
        result += text[cursor...]
        return result
    }

    private static func decodeReference(_ reference: Substring) -> String? {
        if reference.hasPrefix("#") {
            let digits = reference.dropFirst()
            let value: UInt32?
            if digits.first == "x" || digits.first == "X" {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return named[String(reference)]
    }

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "ndash": "–", "mdash": "—", "minus": "−", "hyphen": "‐", "shy": "\u{00AD}",
        "lsquo": "‘", "rsquo": "’", "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›", "prime": "′", "Prime": "″",
        "hellip": "…", "bull": "•", "middot": "·", "deg": "°", "times": "×", "divide": "÷",
        "plusmn": "±", "frasl": "⁄", "frac12": "½", "frac14": "¼", "frac34": "¾", "frac13": "⅓",
        "frac23": "⅔", "frac15": "⅕", "frac25": "⅖", "frac35": "⅗", "frac45": "⅘", "frac16": "⅙",
        "frac56": "⅚", "frac18": "⅛", "frac38": "⅜", "frac58": "⅝", "frac78": "⅞",
        "sup1": "¹", "sup2": "²", "sup3": "³", "ordm": "º", "ordf": "ª", "micro": "µ",
        "copy": "©", "reg": "®", "trade": "™", "sect": "§", "para": "¶", "dagger": "†", "Dagger": "‡",
        "cent": "¢", "pound": "£", "euro": "€", "yen": "¥", "iexcl": "¡", "iquest": "¿",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwnj": "\u{200C}", "zwj": "\u{200D}",
        "aacute": "á", "Aacute": "Á", "agrave": "à", "Agrave": "À", "acirc": "â", "Acirc": "Â",
        "auml": "ä", "Auml": "Ä", "atilde": "ã", "Atilde": "Ã", "aring": "å", "Aring": "Å",
        "aelig": "æ", "AElig": "Æ", "ccedil": "ç", "Ccedil": "Ç",
        "eacute": "é", "Eacute": "É", "egrave": "è", "Egrave": "È", "ecirc": "ê", "Ecirc": "Ê",
        "euml": "ë", "Euml": "Ë", "iacute": "í", "Iacute": "Í", "igrave": "ì", "Igrave": "Ì",
        "icirc": "î", "Icirc": "Î", "iuml": "ï", "Iuml": "Ï", "ntilde": "ñ", "Ntilde": "Ñ",
        "oacute": "ó", "Oacute": "Ó", "ograve": "ò", "Ograve": "Ò", "ocirc": "ô", "Ocirc": "Ô",
        "ouml": "ö", "Ouml": "Ö", "otilde": "õ", "Otilde": "Õ", "oslash": "ø", "Oslash": "Ø",
        "oelig": "œ", "OElig": "Œ", "szlig": "ß", "uacute": "ú", "Uacute": "Ú", "ugrave": "ù",
        "Ugrave": "Ù", "ucirc": "û", "Ucirc": "Û", "uuml": "ü", "Uuml": "Ü", "yacute": "ý",
        "Yacute": "Ý", "yuml": "ÿ",
    ]
}
