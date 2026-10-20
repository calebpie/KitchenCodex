import Foundation

/// Reading order by recursive XY cut: split the blocks at a clear gap, down a gutter between
/// columns or across between bands, and read the parts left to right or top to bottom.
///
/// Which cut comes first decides the order. A gutter both of whose sides run most of the region's
/// height is two columns (two recipes side by side, ingredients beside steps) and is cut first. A
/// gap across of at least `sectionGap` line heights is a break between sections (a title above an
/// ingredient band, the band above the method) and is cut next, so a centered title is read before
/// the ingredient column that starts left of it. Any other gutter comes before the small gaps
/// between paragraphs or ingredient groups, so a column is read whole even beside a shorter one.
enum ReadingOrder {
    /// Share of the region's height each side of a gutter must span to be cut before any band gap.
    static let tallColumns = 0.75
    /// A gap across this many line heights or more is a break between sections.
    static let sectionGap = 2.5
    /// Narrowest gutter that separates columns.
    static let minimumGutter = 0.008

    static func sorted(_ blocks: [PageBlock]) -> [PageBlock] {
        let sizes = blocks.filter { $0.kind != .photo }.map(\.typeSize).filter { $0 > 0 }.sorted()
        let lineHeight = sizes.isEmpty ? 0.012 : sizes[sizes.count / 2]
        // A folio or running head set apart in the margin reads last (or first, at the top): left in,
        // a centred folio bridges the spine of a spread and hides its gutter.
        var body = blocks
        var head: [PageBlock] = [], foot: [PageBlock] = []
        for _ in 0..<3 {
            guard let index = body.indices.max(by: { body[$0].rect.minY < body[$1].rect.minY }),
                  isMarginLine(body[index], others: body, below: true, lineHeight: lineHeight) else { break }
            foot.insert(body.remove(at: index), at: 0)
        }
        for _ in 0..<2 {
            guard let index = body.indices.min(by: { body[$0].rect.minY < body[$1].rect.minY }),
                  isMarginLine(body[index], others: body, below: false, lineHeight: lineHeight) else { break }
            head.append(body.remove(at: index))
        }
        return head + cut(body, lineHeight: lineHeight, depth: 0) + foot
    }

    /// A short line of small type with a clear gap between it and the rest of the page.
    private static func isMarginLine(_ block: PageBlock, others: [PageBlock], below: Bool, lineHeight: Double) -> Bool {
        guard block.kind != .photo, block.lines.count == 1, block.characterCount <= 40, block.typeSize <= lineHeight * 1.1 else { return false }
        let rest = others.filter { $0 != block }
        guard !rest.isEmpty else { return false }
        let gap = below
            ? block.rect.minY - (rest.map(\.rect.maxY).filter { $0 <= block.rect.maxY }.max() ?? 0)
            : (rest.map(\.rect.minY).filter { $0 >= block.rect.minY }.min() ?? 1) - block.rect.maxY
        return gap >= lineHeight * 1.2
    }

    private static func cut(_ blocks: [PageBlock], lineHeight: Double, depth: Int) -> [PageBlock] {
        guard blocks.count > 1, depth < 60 else { return blocks }
        let down = gaps(blocks.map { interval($0.rect.minX, $0.rect.maxX) }).filter { $0.size >= minimumGutter }
        let across = gaps(blocks.map { interval($0.rect.minY, $0.rect.maxY) })
        let top = blocks.map(\.rect.minY).min() ?? 0, bottom = blocks.map(\.rect.maxY).max() ?? 1
        let regionHeight = max(bottom - top, 0.0001)

        func split(down gap: Gap) -> ([PageBlock], [PageBlock]) {
            (blocks.filter { center($0.rect.minX, $0.rect.maxX) < gap.position },
             blocks.filter { center($0.rect.minX, $0.rect.maxX) >= gap.position })
        }
        func split(across gap: Gap) -> ([PageBlock], [PageBlock]) {
            (blocks.filter { center($0.rect.minY, $0.rect.maxY) < gap.position },
             blocks.filter { center($0.rect.minY, $0.rect.maxY) >= gap.position })
        }
        func span(_ part: [PageBlock]) -> Double {
            (part.map(\.rect.maxY).max() ?? 0) - (part.map(\.rect.minY).min() ?? 0)
        }

        var parts: ([PageBlock], [PageBlock])?
        let tall = down.filter { gap in
            let (left, right) = split(down: gap)
            return span(left) >= regionHeight * tallColumns && span(right) >= regionHeight * tallColumns
        }
        if let gutter = tall.max(by: { $0.size < $1.size }) {
            parts = split(down: gutter)
        } else if let gap = across.max(by: { $0.size < $1.size }), gap.size >= lineHeight * sectionGap {
            parts = split(across: gap)
        } else if let gutter = down.max(by: { $0.size < $1.size }) {
            parts = split(down: gutter)
        } else if let gap = across.max(by: { $0.size < $1.size }) {
            parts = split(across: gap)
        }
        guard let (first, second) = parts, !first.isEmpty, !second.isEmpty else {
            return blocks.sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
        }
        return cut(first, lineHeight: lineHeight, depth: depth + 1) + cut(second, lineHeight: lineHeight, depth: depth + 1)
    }

    private static func center(_ low: Double, _ high: Double) -> Double { (low + high) / 2 }

    /// A block's extent, trimmed a little at each end: a photographed page is never square to the
    /// camera, so neighbouring blocks' bounds overlap slightly where the print does not.
    private static func interval(_ low: Double, _ high: Double) -> (Double, Double) {
        let trim = min(0.004, (high - low) * 0.15)
        return (low + trim, high - trim)
    }

    struct Gap {
        var position: Double
        var size: Double
    }

    /// The clear stretches between the merged intervals.
    private static func gaps(_ intervals: [(Double, Double)]) -> [Gap] {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        guard var end = sorted.first?.1 else { return [] }
        var result: [Gap] = []
        for (low, high) in sorted.dropFirst() {
            if low > end {
                result.append(Gap(position: (low + end) / 2, size: low - end))
            }
            end = max(end, high)
        }
        return result
    }
}
