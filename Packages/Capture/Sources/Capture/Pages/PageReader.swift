import CoreGraphics
import Foundation
import ImageIO
import Vision

/// What `PageReader` saw on one image: blocks in reading order, where the page is, and how long it
/// took.
public struct PageScan: Sendable {
    /// Blocks in reading order; a block's `id` is its index here.
    public var blocks: [PageBlock]
    /// The image's size in pixels as read (orientation applied).
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Quarter turns counterclockwise the page was read at, beyond its EXIF orientation: 0 for a page
    /// shot upright, 1 or 3 for a book turned sideways on the table (3 is a quarter turn clockwise).
    /// Rects are in the turned frame.
    public var quarterTurns: Int
    /// The paper: the largest bright, unsaturated area of the image (the page or the spread), nil
    /// when the image is all photo or all background.
    public var paper: PageRect?
    /// Share of the image that is paper (1 when it was not measured): low for a photo plate.
    public var paperFraction: Double = 1
    /// The rows and columns that are mostly paper: the page without the margin `paper` allows for
    /// a shadowed foot. Nil when not measured.
    public var pageCore: PageRect?
    public var duration: Duration

    public init(blocks: [PageBlock], pixelWidth: Int = 0, pixelHeight: Int = 0, quarterTurns: Int = 0, paper: PageRect? = nil, duration: Duration = .zero) {
        self.blocks = blocks
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.quarterTurns = quarterTurns
        self.paper = paper
        self.duration = duration
    }

    /// Text blocks only.
    public var textBlocks: [PageBlock] { blocks.filter { $0.kind != .photo } }
}

/// Reads a photographed page with Vision's `RecognizeDocumentsRequest` (01 §2.3): paragraphs, the
/// recognizer's list items and tables, each line with its transcript, bounds and confidence, plus
/// the page's printed photos, in reading order.
///
/// A photo of an open book sets body text at about a hundredth of the image's height, well under
/// the recognizer's default minimum (a 32nd), which reads such text as if from a much smaller
/// image ("mincod garlc" for "minced garlic"); `minimumTextHeight` sets it to the page. A book
/// turned sideways on the table reads as tall, narrow lines; the reader turns it a quarter each way
/// and keeps the reading with more horizontal text.
public struct PageReader: Sendable {
    /// Smallest text height Vision looks for, as a fraction of the image height.
    public var minimumTextHeight: Float
    /// Long side the image is read at; nil reads the file at full size. Rects are unit page
    /// coordinates either way.
    public var maxPixelSize: Int?
    /// Whether to look for printed photos (cheap: a 400-pixel copy).
    public var findsPhotos: Bool

    public init(minimumTextHeight: Float = 0.006, maxPixelSize: Int? = nil, findsPhotos: Bool = true) {
        self.minimumTextHeight = minimumTextHeight
        self.maxPixelSize = maxPixelSize
        self.findsPhotos = findsPhotos
    }

    public func read(contentsOf url: URL) async throws -> PageScan {
        let clock = ContinuousClock()
        let start = clock.now
        let image = try PageImage.load(contentsOf: url, maxPixelSize: maxPixelSize)
        var scan = try await read(image)
        scan.duration = clock.now - start
        return scan
    }

    public func read(_ image: CGImage) async throws -> PageScan {
        let clock = ContinuousClock()
        let start = clock.now
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.minimumTextHeightFraction = minimumTextHeight
        request.textRecognitionOptions.useLanguageCorrection = true

        var turns = 0
        var observation = try await request.perform(on: image, orientation: .up).first
        if let document = observation?.document, Self.readsSideways(document) {
            // The book was turned on the table: try a quarter turn each way and keep the better.
            var best = (turns: 0, observation: observation, score: Self.horizontalScore(document))
            for (quarter, orientation) in [(1, CGImagePropertyOrientation.left), (3, .right)] {
                let candidate = try await request.perform(on: image, orientation: orientation).first
                let score = candidate.map { Self.horizontalScore($0.document) } ?? 0
                if score > best.score { best = (quarter, candidate, score) }
            }
            turns = best.turns
            observation = best.observation
        }

        let turnedWidth = turns % 2 == 0 ? image.width : image.height
        let turnedHeight = turns % 2 == 0 ? image.height : image.width
        let aspect = Double(turnedWidth) / Double(max(1, turnedHeight))
        var blocks = observation.map { Self.blocks(from: $0.document, aspect: aspect) } ?? []

        var paper: PageRect?
        var pageCore: PageRect?
        var paperFraction = 1.0
        if findsPhotos, let layout = PaperLayout.measure(image, quarterTurns: turns, text: blocks.map(\.rect)) {
            paper = layout.paper
            pageCore = layout.core
            paperFraction = layout.paperFraction
            // A few words near the top or bottom of the frame on something that isn't the page: a
            // sticky note, the cutting mat's print, a price band on the jacket.
            for index in blocks.indices where blocks[index].lines.count <= 2 && blocks[index].characterCount <= 40 {
                let rect = blocks[index].rect
                guard let paper, rect.coverage(by: paper) < 0.9 else { continue }
                if layout.paperShare(around: rect) < 0.35 { blocks[index].role = .ignore }
            }
            blocks += layout.photos.map { PageBlock(id: 0, kind: .photo, rect: $0) }
        }
        // Text cut off by the image's edge (the facing page, the next one under it) or off the paper
        // (the cutting mat, a price sticker on the table) is no part of the page; it reads last.
        for index in blocks.indices where Self.isOffPage(blocks[index].rect, paper: paper) {
            blocks[index].role = .ignore
        }
        let onPage = blocks.filter { $0.role != .ignore }
        let offPage = blocks.filter { $0.role == .ignore }
        blocks = ReadingOrder.sorted(onPage) + offPage.sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
        for index in blocks.indices { blocks[index].id = index }
        var scan = PageScan(blocks: blocks, pixelWidth: turnedWidth, pixelHeight: turnedHeight, quarterTurns: turns, paper: paper, duration: clock.now - start)
        scan.paperFraction = paperFraction
        scan.pageCore = pageCore
        return scan
    }

    /// The lines in the page's foot and head, read again from a crop where the folio's small type
    /// is large enough for the recognizer: the page-wide pass often misses a letterspaced folio
    /// ("SMALL PLATES · 8"). About a tenth of a second.
    public func marginLines(of image: CGImage, paper: PageRect?) async -> [String] {
        let page = paper ?? .fullPage
        var bands = [PageRect(x: page.minX, y: max(0, page.maxY - page.height * 0.14), width: page.width, height: page.height * 0.14)]
        if page.maxY < 0.97 {
            // A foot in shadow falls outside the paper as measured.
            bands.append(PageRect(x: page.minX, y: page.maxY - 0.02, width: page.width, height: min(0.12, 1 - (page.maxY - 0.02))))
        }
        bands.append(PageRect(x: page.minX, y: page.minY, width: page.width, height: page.height * 0.10))
        var lines: [String] = []
        for band in bands {
            let rect = CGRect(x: band.x * Double(image.width), y: band.y * Double(image.height), width: band.width * Double(image.width), height: band.height * Double(image.height)).integral
            guard rect.width > 10, rect.height > 10, let crop = image.cropping(to: rect) else { continue }
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.minimumTextHeightFraction = 0.02
            let found = (try? await request.perform(on: crop)) ?? []
            lines += found.compactMap { $0.topCandidates(1).first?.string }
        }
        return lines
    }

    // MARK: - From Vision

    /// Paragraphs become blocks; a paragraph the recognizer also read as a list item keeps its
    /// marker. Tables whose cells no paragraph covers become table blocks.
    /// A paragraph's lines split where they fall into separate columns, in the paragraph's order:
    /// lines that overlap across stay together.
    static func columns(of lines: [PageTextLine]) -> [[PageTextLine]] {
        guard lines.count > 1 else { return [lines] }
        var groups: [[PageTextLine]] = []
        for line in lines {
            if let index = groups.firstIndex(where: { group in group.contains { $0.rect.horizontalOverlap(with: line.rect) > 0.2 } }) {
                groups[index].append(line)
            } else {
                groups.append([line])
            }
        }
        guard groups.count > 1 else { return [lines] }
        // Only a real gutter splits: the groups must not overlap across at all.
        let spans = groups.map { group in (group.map(\.rect.minX).min()!, group.map(\.rect.maxX).max()!) }.sorted { $0.0 < $1.0 }
        for (left, right) in zip(spans, spans.dropFirst()) where right.0 < left.1 + 0.005 { return [lines] }
        return groups
    }

    /// Outside the paper, or touching the image's edge.
    static func isOffPage(_ rect: PageRect, paper: PageRect?) -> Bool {
        if rect.minX < 0.004 || rect.maxX > 0.996 || rect.minY < 0.003 || rect.maxY > 0.997 { return true }
        guard let paper else { return false }
        return rect.coverage(by: paper) < 0.5
    }

    static func blocks(from document: DocumentObservation.Container, aspect: Double = 1) -> [PageBlock] {
        var blocks: [PageBlock] = []
        let items = document.lists.flatMap(\.items)
        for paragraph in document.paragraphs {
            let lines = paragraph.lines.compactMap { line(from: $0, aspect: aspect) }
            guard !lines.isEmpty else { continue }
            let text = paragraph.transcript
            let item = items.first { Self.sameText($0.itemString, text) || Self.sameText($0.markerString + $0.itemString, text) }
            // A paragraph that runs from the foot of one column to the head of the next is one
            // paragraph to the recognizer; reading order needs it as a block per column.
            for part in Self.columns(of: lines) {
                let rect = part.dropFirst().reduce(part[0].rect) { $0.union($1.rect) }
                var block = PageBlock(id: blocks.count, kind: part.count == 1 ? .line : .paragraph, rect: rect, lines: part)
                if let item, part == lines {
                    block.kind = .listItem
                    block.marker = item.markerString.trimmingCharacters(in: .whitespaces)
                }
                blocks.append(block)
            }
        }
        for table in document.tables {
            let rect = pageRect(table.boundingRegion.boundingBox)
            let covered = blocks.contains { $0.rect.coverage(by: rect) > 0.5 }
            guard !covered else { continue }
            let lines = table.rows.flatMap { $0 }.flatMap { $0.content.text.lines }.compactMap { line(from: $0, aspect: aspect) }
            guard !lines.isEmpty else { continue }
            blocks.append(PageBlock(id: blocks.count, kind: .table, rect: rect, lines: lines))
        }
        return blocks
    }

    /// `aspect` is the image's width over its height, to measure the line's corners in one unit.
    static func line(from observation: RecognizedTextObservation, aspect: Double = 1) -> PageTextLine? {
        let text = observation.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        func length(_ a: NormalizedPoint, _ b: NormalizedPoint) -> Double {
            let dx = (a.x - b.x) * aspect, dy = a.y - b.y
            return (dx * dx + dy * dy).squareRoot()
        }
        let size = (length(observation.topLeft, observation.bottomLeft) + length(observation.topRight, observation.bottomRight)) / 2
        return PageTextLine(text: text, rect: pageRect(observation.boundingRegion.boundingBox), confidence: Double(observation.confidence), size: size, top: 1 - observation.topLeft.y)
    }

    /// Vision's normalized rect (origin at the bottom left) as a unit page rect (origin top left).
    static func pageRect(_ rect: NormalizedRect) -> PageRect {
        PageRect(x: rect.origin.x, y: 1 - rect.origin.y - rect.height, width: rect.width, height: rect.height)
    }

    private static func sameText(_ a: String, _ b: String) -> Bool {
        let left = ImportText.normalizedForComparison(a), right = ImportText.normalizedForComparison(b)
        return !left.isEmpty && (left == right || (left.count > 12 && right.hasSuffix(left)))
    }

    /// Most of the text runs down the image rather than across.
    static func readsSideways(_ document: DocumentObservation.Container) -> Bool {
        let lines = document.paragraphs.flatMap(\.lines).filter { $0.transcript.count >= 6 }
        guard lines.count >= 4 else { return false }
        let tall = lines.filter { $0.boundingRegion.boundingBox.height > $0.boundingRegion.boundingBox.width * 1.5 }
        return Double(tall.count) > Double(lines.count) * 0.5
    }

    /// Characters on lines that run across, weighted by confidence.
    static func horizontalScore(_ document: DocumentObservation.Container) -> Double {
        document.paragraphs.flatMap(\.lines).reduce(0) { total, line in
            let box = line.boundingRegion.boundingBox
            guard box.width > box.height else { return total }
            return total + Double(line.transcript.count) * Double(line.confidence)
        }
    }
}

// MARK: - Paper and photos

/// The paper and the printed photos on it, from a 400-pixel copy of the image: paper is bright and
/// unsaturated; a printed photo is a large hole in the paper with no text in it.
struct PaperLayout {
    var paper: PageRect?
    var photos: [PageRect]
    /// The paper's share of the image.
    var paperFraction: Double = 0
    /// The rows and columns that are mostly paper.
    var core: PageRect?
    /// Which pixels of the small copy are paper (before text was closed into it), row by row.
    var mask: [Bool] = []
    var width = 0
    var height = 0

    /// The share of paper in a three-pixel ring around `rect`: the background the text is set on.
    func paperShare(around rect: PageRect) -> Double {
        guard width > 0, height > 0 else { return 1 }
        let x0 = Int(rect.minX * Double(width)) - 3, x1 = Int(rect.maxX * Double(width)) + 3
        let y0 = Int(rect.minY * Double(height)) - 3, y1 = Int(rect.maxY * Double(height)) + 3
        var paper = 0, total = 0
        for y in max(0, y0)...min(height - 1, max(0, y1)) {
            for x in max(0, x0)...min(width - 1, max(0, x1)) {
                let inside = x > x0 + 2 && x < x1 - 2 && y > y0 + 2 && y < y1 - 2
                guard !inside else { continue }
                total += 1
                if mask[y * width + x] { paper += 1 }
            }
        }
        return total == 0 ? 1 : Double(paper) / Double(total)
    }

    static let longSide = 400

    static func measure(_ image: CGImage, quarterTurns: Int, text: [PageRect]) -> PaperLayout? {
        guard let (pixels, sourceWidth, sourceHeight) = PageImage.rgbaPixels(of: image, longSide: longSide) else { return nil }
        // Turn the small copy to match the frame the text was read in.
        let (width, height) = quarterTurns % 2 == 0 ? (sourceWidth, sourceHeight) : (sourceHeight, sourceWidth)
        var paperMask = [Bool](repeating: false, count: width * height)
        var lumaSum = 0.0
        var lumas = [Double](repeating: 0, count: width * height)
        var saturations = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let (sx, sy) = sourcePoint(x: x, y: y, width: width, height: height, quarterTurns: quarterTurns)
                let offset = (sy * sourceWidth + sx) * 4
                let r = Double(pixels[offset]) / 255, g = Double(pixels[offset + 1]) / 255, b = Double(pixels[offset + 2]) / 255
                let maxC = max(r, g, b), minC = min(r, g, b)
                let luma = 0.299 * r + 0.587 * g + 0.114 * b
                lumas[y * width + x] = luma
                saturations[y * width + x] = maxC > 0 ? (maxC - minC) / maxC : 0
                lumaSum += luma
            }
        }
        // Paper is near the brightest tones of the image, whatever the exposure.
        let sortedLuma = lumas.sorted()
        let bright = sortedLuma[Int(Double(sortedLuma.count - 1) * 0.95)]
        let threshold = max(0.35, bright * 0.72)
        for index in paperMask.indices {
            paperMask[index] = lumas[index] >= threshold && saturations[index] < 0.28
        }
        // Text is ink on paper: close it into the paper so only pictures remain as holes.
        var textMask = [Bool](repeating: false, count: width * height)
        for rect in text {
            let x0 = max(0, Int(rect.minX * Double(width)) - 1), x1 = min(width - 1, Int(rect.maxX * Double(width)) + 1)
            let y0 = max(0, Int(rect.minY * Double(height)) - 1), y1 = min(height - 1, Int(rect.maxY * Double(height)) + 1)
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 { textMask[y * width + x] = true } }
        }
        let closed = Morphology.close(zip(paperMask, textMask).map { $0 || $1 }, width: width, height: height, radius: 2)

        let components = Morphology.components(closed, width: width, height: height)
        guard let paperComponent = components.max(by: { $0.count < $1.count }),
              Double(paperComponent.count) > Double(width * height) * 0.08 else {
            return PaperLayout(paper: nil, photos: [], paperFraction: Double(components.max(by: { $0.count < $1.count })?.count ?? 0) / Double(width * height), mask: paperMask, width: width, height: height)
        }
        // The paper's bounds from its rows and columns, so the mat's white grid lines joined to the
        // page don't stretch them: the longest run of rows (and columns) that are mostly paper.
        let inComponent = Morphology.componentMask(closed, containing: paperComponent, width: width, height: height)
        func extent(count: Int, length: Int, share: (Int) -> Int) -> (Int, Int) {
            var best = (0, count - 1), bestLength = 0, start: Int?
            for index in 0...count {
                let full = index < count && Double(share(index)) >= Double(length) * 0.3
                if full, start == nil { start = index }
                if !full, let begin = start {
                    if index - begin > bestLength { bestLength = index - begin; best = (begin, index - 1) }
                    start = nil
                }
            }
            return bestLength > 0 ? best : (0, count - 1)
        }
        let rows = extent(count: height, length: width) { y in (0..<width).count { inComponent[y * width + $0] } }
        let columns = extent(count: width, length: rows.1 - rows.0 + 1) { x in (rows.0...rows.1).count { inComponent[$0 * width + x] } }
        // A margin's worth more each way: a page's foot is often in shadow, and its folio with it.
        let component = paperComponent.rect(width: width, height: height)
        let margin = 0.04
        let left = max(component.minX, Double(columns.0) / Double(width) - margin)
        let top = max(component.minY, Double(rows.0) / Double(height) - margin)
        let right = min(component.maxX, Double(columns.1 + 1) / Double(width) + margin)
        let bottom = min(component.maxY, Double(rows.1 + 1) / Double(height) + margin)
        let paperRect = PageRect(x: left, y: top, width: right - left, height: bottom - top)
        let coreRect = PageRect(
            x: Double(columns.0) / Double(width), y: Double(rows.0) / Double(height),
            width: Double(columns.1 - columns.0 + 1) / Double(width), height: Double(rows.1 - rows.0 + 1) / Double(height)
        )

        // Holes: what is not paper inside the paper's bounds, as connected regions.
        var holeMask = [Bool](repeating: false, count: width * height)
        let px0 = Int(paperRect.minX * Double(width)), px1 = min(width - 1, Int(paperRect.maxX * Double(width)))
        let py0 = Int(paperRect.minY * Double(height)), py1 = min(height - 1, Int(paperRect.maxY * Double(height)))
        for y in py0...py1 {
            for x in px0...px1 where !closed[y * width + x] {
                holeMask[y * width + x] = true
            }
        }
        let opened = Morphology.open(holeMask, width: width, height: height, radius: 2)
        let paperArea = paperRect.area
        var photos: [PageRect] = []
        for component in Morphology.components(opened, width: width, height: height) {
            let rect = component.rect(width: width, height: height)
            guard rect.area >= paperArea * 0.012, rect.width > 0.04, rect.height > 0.04 else { continue }
            // A picture fills most of its box; the gutter's shadow or a hand along an edge does not.
            let fill = Double(component.count) / (rect.area * Double(width * height))
            guard fill > 0.55 else { continue }
            // Pictures sit on the paper, not along the image's edge where the table shows, nor along the
            // paper's side where the facing page's picture begins.
            // A hand holding the book open comes in over the paper's foot or head.
            let touchesEdge = rect.minX < 0.01 || rect.minY < 0.01 || rect.maxX > 0.99 || rect.maxY > 0.99
                || rect.minX <= paperRect.minX + 0.01 || rect.maxX >= paperRect.maxX - 0.01
                || rect.minY <= paperRect.minY + 0.01 || rect.maxY >= paperRect.maxY - 0.01
            if touchesEdge, rect.area < paperArea * 0.25 { continue }
            photos.append(rect)
        }
        return PaperLayout(paper: paperRect, photos: photos, paperFraction: Double(paperComponent.count) / Double(width * height), core: coreRect, mask: paperMask, width: width, height: height)
    }

    /// The pixel in the unturned copy that shows at (x, y) of the turned frame.
    private static func sourcePoint(x: Int, y: Int, width: Int, height: Int, quarterTurns: Int) -> (Int, Int) {
        switch quarterTurns % 4 {
        case 1: (height - 1 - y, x)  // read with orientation .left: the frame is the source turned counterclockwise
        case 3: (y, width - 1 - x)
        case 2: (width - 1 - x, height - 1 - y)
        default: (x, y)
        }
    }
}

/// Binary-mask morphology on small images.
enum Morphology {
    struct Component {
        var count = 0
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min

        func rect(width: Int, height: Int) -> PageRect {
            PageRect(
                x: Double(minX) / Double(width), y: Double(minY) / Double(height),
                width: Double(maxX - minX + 1) / Double(width), height: Double(maxY - minY + 1) / Double(height)
            )
        }
    }

    static func dilate(_ mask: [Bool], width: Int, height: Int, radius: Int) -> [Bool] {
        // Separable: rows, then columns.
        var rows = [Bool](repeating: false, count: mask.count)
        for y in 0..<height {
            for x in 0..<width {
                var hit = false
                for dx in max(0, x - radius)...min(width - 1, x + radius) where mask[y * width + dx] { hit = true; break }
                rows[y * width + x] = hit
            }
        }
        var result = [Bool](repeating: false, count: mask.count)
        for y in 0..<height {
            for x in 0..<width {
                var hit = false
                for dy in max(0, y - radius)...min(height - 1, y + radius) where rows[dy * width + x] { hit = true; break }
                result[y * width + x] = hit
            }
        }
        return result
    }

    static func erode(_ mask: [Bool], width: Int, height: Int, radius: Int) -> [Bool] {
        dilate(mask.map { !$0 }, width: width, height: height, radius: radius).map { !$0 }
    }

    static func close(_ mask: [Bool], width: Int, height: Int, radius: Int) -> [Bool] {
        erode(dilate(mask, width: width, height: height, radius: radius), width: width, height: height, radius: radius)
    }

    static func open(_ mask: [Bool], width: Int, height: Int, radius: Int) -> [Bool] {
        dilate(erode(mask, width: width, height: height, radius: radius), width: width, height: height, radius: radius)
    }

    /// The pixels of `component` (found by `components`), as a mask: the component containing its
    /// first pixel scanned.
    static func componentMask(_ mask: [Bool], containing component: Component, width: Int, height: Int) -> [Bool] {
        var result = [Bool](repeating: false, count: mask.count)
        guard let start = (component.minY...component.maxY).lazy.flatMap({ y in (component.minX...component.maxX).lazy.map { y * width + $0 } })
            .first(where: { mask[$0] }) else { return result }
        var stack = [start]
        result[start] = true
        while let index = stack.popLast() {
            let x = index % width, y = index / width
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < width && ny < height {
                let neighbor = ny * width + nx
                if mask[neighbor] && !result[neighbor] {
                    result[neighbor] = true
                    stack.append(neighbor)
                }
            }
        }
        return result
    }

    /// 4-connected components of the set pixels.
    static func components(_ mask: [Bool], width: Int, height: Int) -> [Component] {
        var seen = [Bool](repeating: false, count: mask.count)
        var result: [Component] = []
        var stack: [Int] = []
        for start in mask.indices where mask[start] && !seen[start] {
            var component = Component()
            stack.append(start)
            seen[start] = true
            while let index = stack.popLast() {
                let x = index % width, y = index / width
                component.count += 1
                component.minX = min(component.minX, x); component.maxX = max(component.maxX, x)
                component.minY = min(component.minY, y); component.maxY = max(component.maxY, y)
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let neighbor = ny * width + nx
                    if mask[neighbor] && !seen[neighbor] {
                        seen[neighbor] = true
                        stack.append(neighbor)
                    }
                }
            }
            result.append(component)
        }
        return result
    }
}
