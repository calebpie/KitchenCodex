import Foundation

/// A rectangle in unit page coordinates: the image as shown (orientation applied), x and y from 0
/// to 1 across and down from the top left. Independent of the image's pixel size, so a page read
/// from a downscaled copy keeps the same rects.
public struct PageRect: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = PageRect(x: 0, y: 0, width: 0, height: 0)
    public static let fullPage = PageRect(x: 0, y: 0, width: 1, height: 1)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { max(0, width) * max(0, height) }

    public func union(_ other: PageRect) -> PageRect {
        let left = min(minX, other.minX), top = min(minY, other.minY)
        return PageRect(x: left, y: top, width: max(maxX, other.maxX) - left, height: max(maxY, other.maxY) - top)
    }

    public func intersection(_ other: PageRect) -> PageRect? {
        let left = max(minX, other.minX), right = min(maxX, other.maxX)
        let top = max(minY, other.minY), bottom = min(maxY, other.maxY)
        guard right > left, bottom > top else { return nil }
        return PageRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The share of this rect's area that `other` covers.
    public func coverage(by other: PageRect) -> Double {
        guard area > 0, let overlap = intersection(other) else { return 0 }
        return overlap.area / area
    }

    /// How much the two overlap across, as a share of the narrower one.
    public func horizontalOverlap(with other: PageRect) -> Double {
        let overlap = min(maxX, other.maxX) - max(minX, other.minX)
        let narrower = min(width, other.width)
        guard narrower > 0 else { return 0 }
        return max(0, overlap) / narrower
    }

    /// How much the two overlap down, as a share of the shorter one.
    public func verticalOverlap(with other: PageRect) -> Double {
        let overlap = min(maxY, other.maxY) - max(minY, other.minY)
        let shorter = min(height, other.height)
        guard shorter > 0 else { return 0 }
        return max(0, overlap) / shorter
    }

    /// The gap between the two rects, 0 when they touch or overlap.
    public func distance(to other: PageRect) -> Double {
        let dx = max(0, max(other.minX - maxX, minX - other.maxX))
        let dy = max(0, max(other.minY - maxY, minY - other.maxY))
        return (dx * dx + dy * dy).squareRoot()
    }

    public var description: String {
        String(format: "(%.3f, %.3f, %.3f × %.3f)", x, y, width, height)
    }
}

/// One line of text as the reader saw it.
public struct PageTextLine: Sendable, Equatable, Hashable {
    public var text: String
    public var rect: PageRect
    /// The recognizer's confidence, 0…1.
    public var confidence: Double
    /// The line's height across its own baseline, as a fraction of the page height: the type-size
    /// cue. Taken from the line's corners rather than its bounds, which grow with the page's tilt.
    /// Capitals and lowercase lines differ a little; a title and body text a lot.
    public var size: Double
    /// The y of the line's top at its left end: where it starts down the page whatever the page's
    /// tilt, to measure the space between lines.
    public var top: Double

    public init(text: String, rect: PageRect, confidence: Double, size: Double? = nil, top: Double? = nil) {
        self.text = text
        self.rect = rect
        self.confidence = confidence
        self.size = size ?? rect.height
        self.top = top ?? rect.minY
    }
}

/// A block of a page in reading order: a heading, a paragraph, a lone line, a list, a table, or a
/// printed photo, with where it sits and what the structurer made of it.
public struct PageBlock: Sendable, Equatable, Identifiable {
    /// What the reader saw.
    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// Short text set clearly larger than the body.
        case heading
        /// Several lines of text, or one line of running text.
        case paragraph
        /// One short line: an ingredient, a label, a folio.
        case line
        /// A list item the recognizer marked (a number or bullet before it).
        case listItem
        case table
        /// A printed picture: a photo with no text in it.
        case photo
    }

    /// What the block is in the recipe (the review's region labels, 03 §3.6).
    public enum Role: String, Sendable, Codable, CaseIterable {
        case title
        case yield
        case time
        case headnote
        case ingredient
        case ingredientGroup
        case step
        case note
        case stepPhoto
        /// Running heads, folios, page numbers.
        case furniture
        /// "PHOTOGRAPH ON PAGE 6" and other pointers set on their own.
        case crossReference
        /// Outside the page (the table, the facing page's edge), or a photo plate's picture.
        case ignore
    }

    /// Position in reading order.
    public var id: Int
    public var kind: Kind
    public var role: Role?
    public var rect: PageRect
    public var lines: [PageTextLine]
    /// The marker the recognizer read before a list item ("2", "•").
    public var marker: String?
    /// Which image of a stitched reading the block came from (0 for the first).
    public var file: Int
    /// The structured item the block became, in the order of its kind (the ingredient line, the
    /// step); for a step photo, the step it belongs to.
    public var item: Int?
    /// Which recipe on the page the block belongs to, when the page holds several.
    public var recipe: Int?

    public init(id: Int, kind: Kind, rect: PageRect, lines: [PageTextLine] = [], marker: String? = nil, file: Int = 0) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.lines = lines
        self.marker = marker
        self.file = file
    }

    /// The block's text, lines joined with spaces (hyphenated line ends rejoined).
    public var text: String { PageText.join(lines.map(\.text)) }

    /// The lowest line confidence pulls the block down a little; a photo has none.
    public var confidence: Double {
        guard !lines.isEmpty else { return kind == .photo ? 1 : 0 }
        let mean = lines.map(\.confidence).reduce(0, +) / Double(lines.count)
        return mean
    }

    /// The median line height: the type-size cue.
    public var typeSize: Double {
        let sizes = lines.map(\.size).sorted()
        guard !sizes.isEmpty else { return 0 }
        return sizes[sizes.count / 2]
    }

    public var characterCount: Int { lines.reduce(0) { $0 + $1.text.count } }
}

/// Text joining shared by the page reader and structurer.
enum PageText {
    /// Lines of one paragraph as a single string: a line ending in a hyphen after a letter joins the
    /// next without a space ("re-" "move" → "remove"), unless the next starts with a capital or the
    /// hyphen is part of a compound the page breaks there ("2-" "to 3-quart" keeps its hyphen).
    static func join(_ lines: [String]) -> String {
        var result = ""
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if result.isEmpty {
                result = line
            } else if result.hasSuffix("-"), result.dropLast().last?.isLetter == true,
                      line.first?.isLowercase == true {
                result.removeLast()
                result += line
            } else if result.hasSuffix("—") || result.hasSuffix("–") || result.hasSuffix("/") {
                result += line
            } else {
                result += " " + line
            }
        }
        return result
    }
}
