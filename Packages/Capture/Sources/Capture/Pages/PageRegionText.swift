import Foundation

/// A region's printed lines as a part of the recipe, for scan review when the cook reassigns a
/// region (03 §3.6): the same cleanup the structurer gives the parts it reads itself.
public enum PageRegionText {
    /// A title: its lines joined, capitals in title case, a second-language name after it left out
    /// (ux-notes row 59).
    public static func title(_ lines: [String]) -> String {
        PageLines.titleText(PageLines.titleWithoutAlternate(lines, pageLanguage: PageLines.readerLanguage))
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
