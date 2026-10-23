import Foundation

/// A recipe's page layout as a short string for `Book.reviewedLayouts` (02 Flow B step 5, 03 §3.6:
/// "the structurer compares column count, block order and typographic cues"): how the title is set
/// (letterspaced capitals, centred or flush left, or set larger than the body), where the
/// ingredients sit against the method and in how many columns, and whether the method is numbered
/// and in how many columns. It is the same for pages of one layout, whatever the recipe's length or
/// its title's, and differs between the fixture books. A title set larger and close carries no
/// alignment: a long one fills the measure and reads as centred and flush left alike.
///
/// `t:wc i:above-n m:para-2` reads: title in letterspaced capitals, centred; ingredients above the
/// method in several columns; the method in paragraphs over two columns.
enum LayoutSignature {
    struct Input {
        /// The title's narrowest line; nil when the reading has no title.
        var title: PageRect?
        var titleIsWide: Bool
        var region: PageRect
        var ingredientLines: [PageRect]
        var methodLines: [PageRect]
        var numbered: Bool
    }

    /// Whether `signature` is a layout the cook has confirmed (ux-notes row 125): one of
    /// `confirmed` as it is, or, once the book has a confirmed layout, one whose title and method
    /// are set the same way and that differs only in where the ingredients sit. A book that
    /// places a sub-recipe's ingredients beside the method on one page and under it on the next
    /// has one layout to the cook.
    static func matches(_ signature: String, confirmed: Set<String>) -> Bool {
        if confirmed.contains(signature) { return true }
        guard !confirmed.isEmpty else { return false }
        let parts = withoutIngredients(signature)
        return confirmed.contains { withoutIngredients($0) == parts }
    }

    /// The title and method parts of a signature.
    static func withoutIngredients(_ signature: String) -> String {
        signature.split(separator: " ").filter { !$0.hasPrefix("i:") }.joined(separator: " ")
    }

    static func make(_ input: Input) -> String {
        let title: String
        if let block = input.title {
            if input.titleIsWide {
                // Letterspaced capitals are centred over the recipe or set flush left; the margins
                // either side say which (a title as wide as the text counts as centred).
                let leftMargin = block.minX - input.region.minX, rightMargin = input.region.maxX - block.maxX
                title = abs(leftMargin - rightMargin) < max(0.05, input.region.width * 0.12) ? "wc" : "wl"
            } else {
                title = "s"
            }
        } else {
            title = "-"
        }

        let ingredients: String
        if input.ingredientLines.isEmpty {
            ingredients = "none"
        } else {
            let box = input.ingredientLines.dropFirst().reduce(input.ingredientLines[0]) { $0.union($1) }
            let place: String
            if let method = input.methodLines.first.map({ first in input.methodLines.dropFirst().reduce(first) { $0.union($1) } }) {
                if box.maxY <= method.minY + 0.02 { place = "above" }
                else if box.maxX <= method.minX + 0.02 { place = "left" }
                else if box.minX >= method.maxX - 0.02 { place = "right" }
                else { place = "mixed" }
            } else {
                place = "only"
            }
            ingredients = place + "-" + (columns(input.ingredientLines) > 1 ? "n" : "1")
        }
        let method = (input.numbered ? "num" : "para") + "-" + String(min(2, max(1, columns(input.methodLines))))
        return "t:\(title) i:\(ingredients) m:\(input.methodLines.isEmpty ? "none" : method)"
    }

    /// Columns among the lines: groups whose horizontal extents do not overlap.
    static func columns(_ rects: [PageRect]) -> Int {
        var spans: [(Double, Double)] = []
        for rect in rects.sorted(by: { $0.minX < $1.minX }) {
            // Trim each line's span so a long line does not bridge a gutter it only touches.
            let low = rect.minX + 0.01, high = max(rect.minX + 0.02, rect.maxX - 0.01)
            if let last = spans.last, low <= last.1 {
                spans[spans.count - 1].1 = max(last.1, high)
            } else {
                spans.append((low, high))
            }
        }
        return spans.count
    }
}
