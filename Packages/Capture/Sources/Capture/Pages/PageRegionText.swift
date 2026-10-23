import Foundation

/// A region's printed lines as a part of the recipe, for scan review when the cook reassigns a
/// region (03 §3.6): the same cleanup the structurer gives the parts it reads itself.
public enum PageRegionText {
    /// A title: its lines joined, capitals in title case, a second-language name after it left out
    /// (ux-notes row 59).
    public static func title(_ lines: [String]) -> String {
        PageLines.mendTitleDash(PageLines.titleText(PageLines.titleWithoutAlternate(lines, pageLanguage: PageLines.readerLanguage)))
    }

    /// A yield as the app shows it ("MAKES 2 CUPS" → "Makes 2 cups").
    public static func yield(_ lines: [String]) -> String {
        PageLines.yieldText(PageText.join(lines))
    }

    /// A step, a headnote or a note: one printed paragraph, never split (04 §5.1 "Step
    /// granularity"), hyphenated line ends rejoined.
    public static func paragraph(_ lines: [String]) -> String {
        PageText.join(lines)
    }

    /// Whether a scanned ingredient line asks for a look: its amount went unread, or nothing read as
    /// the item. A line with no amount ("Kosher salt") reads cleanly (ux-notes rows 58 and 67).
    public static func isUnreadIngredient(_ line: String) -> Bool {
        PageLines.isUnparsed(line, parsed: IngredientParser.parse(line))
    }

    /// Regions combined into one (scan review's Combine, ux-notes row 88), given in reading order
    /// with their rects and printed lines: their lines as the page prints them, a piece set on the
    /// same printed line as the end of the piece before (a bold label and the note it opens, a step
    /// a shadow broke) continuing that line, any other starting a line of its own; and the rect
    /// around them all. Pieces opening on one line that the reader put out of order are read left to
    /// right, a run-in label first.
    public static func combined(_ pieces: [(rect: PageRect, lines: [String])]) -> (rect: PageRect, lines: [String]) {
        guard var rect = pieces.first?.rect else { return (.zero, []) }
        /// The top or bottom printed line of a piece, from its rect and line count.
        func line(_ piece: (rect: PageRect, lines: [String]), last: Bool) -> PageRect {
            let height = piece.rect.height / Double(max(1, piece.lines.count))
            return PageRect(x: piece.rect.minX, y: last ? piece.rect.maxY - height : piece.rect.minY, width: piece.rect.width, height: height)
        }
        func sameLine(_ a: PageRect, _ b: PageRect) -> Bool {
            let shorter = min(a.height, b.height)
            guard shorter > 0 else { return false }
            return (min(a.maxY, b.maxY) - max(a.minY, b.minY)) / shorter >= 0.5
        }
        // Pieces that open on one printed line: the one-line pieces left to right, then a piece that
        // wraps on from that line (its box starts at the margin, its first words after the others):
        // a run-in label ("NOTE"), the phrase beside it, the rest of the note.
        func precedes(_ a: (rect: PageRect, lines: [String]), _ b: (rect: PageRect, lines: [String])) -> Bool {
            let (wrapsA, wrapsB) = (a.lines.count > 1, b.lines.count > 1)
            return wrapsA == wrapsB ? a.rect.minX < b.rect.minX - 0.01 : !wrapsA
        }
        var ordered = pieces
        var swapped = true
        var passes = 0
        while swapped, passes < ordered.count {
            swapped = false
            passes += 1
            for index in ordered.indices.dropFirst() where sameLine(line(ordered[index - 1], last: false), line(ordered[index], last: false))
                && precedes(ordered[index], ordered[index - 1]) {
                ordered.swapAt(index - 1, index)
                swapped = true
            }
        }
        var lines: [String] = []
        var previous: (rect: PageRect, lines: [String])?
        for piece in ordered where !piece.lines.isEmpty {
            rect = rect.union(piece.rect)
            if let before = previous, !lines.isEmpty, sameLine(line(before, last: true), line(piece, last: false)) {
                lines[lines.count - 1] = PageText.join([lines[lines.count - 1], piece.lines[0]])
                lines += piece.lines.dropFirst()
            } else {
                lines += piece.lines
            }
            previous = piece
        }
        return (rect, lines)
    }

    /// Ingredient lines, one per printed line, OCR's fraction slips mended; a line that opens in
    /// lowercase or carries no amount after a line ending in a comma wraps the one before.
    public static func ingredientLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        for raw in lines {
            let line = PageLines.ingredientText(raw)
            guard !line.isEmpty else { continue }
            if let last = result.last, line.first?.isLowercase == true || (last.hasSuffix(",") && IngredientParser.parse(line).quantity == nil) {
                result[result.count - 1] = PageText.join([last, line])
            } else {
                result.append(line)
            }
        }
        return result
    }
}
