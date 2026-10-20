import Capture
import SwiftUI
import UIKit

/// A recipe laid out as a document page: US Letter or A4 by the locale's measurement system, 0.75 in
/// margins, the title, source, metadata and cover on the first page, then ingredients beside steps
/// in two columns that continue onto later pages, the notes after both, and the title and page
/// numbers in the footer. The ingredients column hugs its longest line between 2.4 in and a third of
/// the text width, as the wide detail's does (04 §5.1 iPad columns); a page too narrow to keep the
/// steps readable beside it stacks them instead. No block (a line, a step, a note paragraph) is
/// split across pages, and a heading is never left without the block after it. Made with SwiftUI
/// and drawn into a PDF by `ImageRenderer`.
enum RecipePDFRenderer {
    /// The sheet the PDF is set on.
    struct Paper: Equatable {
        var size: CGSize

        static let letter = Paper(size: CGSize(width: 612, height: 792))
        static let a4 = Paper(size: CGSize(width: 595.28, height: 841.89))

        /// US Letter where the locale measures in US units, A4 elsewhere.
        static var current: Paper { Locale.current.measurementSystem == .us ? .letter : .a4 }
    }

    /// 0.75 in.
    static let margin: CGFloat = 54
    static let footerHeight: CGFloat = 22
    static let columnGap: CGFloat = 28
    static let blockSpacing: CGFloat = 7
    /// Between the header or the columns and what follows them.
    static let sectionGap: CGFloat = 20
    /// The ingredients column's narrowest width, 2.4 in.
    static let ingredientsMinimum: CGFloat = 172.8
    /// The narrowest steps column worth setting beside the ingredients, 3.5 in (about 60 characters).
    static let stepsMinimum: CGFloat = 252

    /// The widths a recipe is set at on a paper.
    struct Layout {
        var paper: Paper
        var textWidth: CGFloat
        var ingredientsWidth: CGFloat
        var isSideBySide: Bool

        var stepsWidth: CGFloat { textWidth - columnGap - ingredientsWidth }
        /// Height for content on a page, between the margins and above the footer.
        var bodyHeight: CGFloat { paper.size.height - margin * 2 - footerHeight }
    }

    /// The PDF's bytes. The cover is decoded at print size off the main actor; layout and drawing
    /// happen on it, as `ImageRenderer` requires.
    static func pdf(for recipe: ExportRecipe, coverData: Data?, paper: Paper = .current) async -> Data {
        var cover: UIImage?
        if let coverData {
            cover = await ImageProcessing.thumbnail(from: coverData, maxPixelSize: 1_400)
        }
        return render(recipe, cover: cover, paper: paper)
    }

    @MainActor
    static func render(_ recipe: ExportRecipe, cover: UIImage?, paper: Paper) -> Data {
        let layout = layout(for: recipe, on: paper)
        let pages = paginate(recipe, cover: cover, layout: layout)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: paper.size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, [
                  kCGPDFContextTitle: recipe.title,
                  kCGPDFContextCreator: "Recipe Codex",
              ] as CFDictionary) else { return Data() }

        for (index, page) in pages.enumerated() {
            let view = PrintPage(
                recipe: recipe,
                cover: cover,
                layout: layout,
                page: page,
                pageNumber: index + 1,
                pageCount: pages.count
            )
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(paper.size)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    /// The ingredients column as wide as its longest line or heading, between 2.4 in and a third of
    /// the text width (the floor wins where a third is narrower), and side by side only when the
    /// steps keep at least 3.5 in beside it.
    @MainActor
    static func layout(for recipe: ExportRecipe, on paper: Paper) -> Layout {
        let textWidth = paper.size.width - margin * 2
        let longest = PrintBlock.ingredients(of: recipe).map { idealWidth($0.view) }.max() ?? 0
        let width = min(max(longest, ingredientsMinimum), max(ingredientsMinimum, textWidth / 3))
        return Layout(
            paper: paper,
            textWidth: textWidth,
            ingredientsWidth: width,
            isSideBySide: textWidth - columnGap - width >= stepsMinimum
        )
    }

    // MARK: - Pagination

    struct Page {
        var ingredients: [PrintBlock] = []
        var steps: [PrintBlock] = []
        /// Full-width blocks under the columns: the notes once both columns have ended, or the whole
        /// recipe when the page stacks.
        var below: [PrintBlock] = []
    }

    /// Side by side, the two columns fill page by page and the notes start under the taller one on
    /// the page where both have ended; stacked, everything runs in one full-width column.
    @MainActor
    static func paginate(_ recipe: ExportRecipe, cover: UIImage?, layout: Layout) -> [Page] {
        let header = measure(PrintHeader(recipe: recipe, cover: cover, width: layout.textWidth), width: layout.textWidth) + sectionGap
        // A first page whose cover leaves almost no room still takes a few lines.
        func capacity(_ page: Int) -> CGFloat {
            page == 0 ? max(layout.bodyHeight - header, 120) : layout.bodyHeight
        }

        let ingredients = PrintBlock.ingredients(of: recipe)
        let steps = PrintBlock.steps(of: recipe)
        let notes = PrintBlock.notes(of: recipe)

        guard layout.isSideBySide else {
            let flowed = flow(ingredients + steps + notes, width: layout.textWidth, capacity: capacity)
            return flowed.columns.map { Page(below: $0) }
        }

        let ingredientColumns = flow(ingredients, width: layout.ingredientsWidth, capacity: capacity)
        let stepColumns = flow(steps, width: layout.stepsWidth, capacity: capacity)
        var pages = (0..<max(ingredientColumns.columns.count, stepColumns.columns.count, 1)).map { index in
            Page(
                ingredients: index < ingredientColumns.columns.count ? ingredientColumns.columns[index] : [],
                steps: index < stepColumns.columns.count ? stepColumns.columns[index] : []
            )
        }
        guard !notes.isEmpty else { return pages }

        // The notes go under whichever column ends lower on the last page.
        let last = pages.count - 1
        let ingredientsUsed = ingredientColumns.columns.count - 1 == last ? ingredientColumns.lastUsed : 0
        let stepsUsed = stepColumns.columns.count - 1 == last ? stepColumns.lastUsed : 0
        let columnsUsed = max(ingredientsUsed, stepsUsed)
        let flowed = flow(notes, width: layout.textWidth, from: last, used: columnsUsed > 0 ? columnsUsed + sectionGap : 0, capacity: capacity)
        for (offset, blocks) in flowed.columns.enumerated() {
            if last + offset < pages.count {
                pages[last + offset].below = blocks
            } else {
                pages.append(Page(below: blocks))
            }
        }
        return pages
    }

    /// Fills a column page by page, starting on `page` with `used` points already taken there,
    /// measuring every block at `width`. A block never splits; one that doesn't fit what is left
    /// starts the next page, and a heading moves with the block after it. Returns each page's
    /// blocks from `page` on (the first may be empty when nothing fit) and the height used on the last.
    @MainActor
    static func flow(_ blocks: [PrintBlock], width: CGFloat, from page: Int = 0, used start: CGFloat = 0, capacity: (Int) -> CGFloat) -> (columns: [[PrintBlock]], lastUsed: CGFloat) {
        var columns: [[PrintBlock]] = [[]]
        var used = start
        let heights = blocks.map { measure($0.view, width: width) }
        for (index, block) in blocks.enumerated() {
            var needed = heights[index]
            // Keep a heading with what follows it.
            if block.isHeading, index + 1 < blocks.count { needed += blockSpacing + heights[index + 1] }
            let spacing = columns[columns.count - 1].isEmpty ? 0 : blockSpacing
            if used + spacing + needed > capacity(page + columns.count - 1), used > 0 {
                columns.append([])
                used = 0
            }
            let gap = columns[columns.count - 1].isEmpty ? 0 : blockSpacing
            columns[columns.count - 1].append(block)
            used += gap + heights[index]
        }
        return (columns, used)
    }

    @MainActor
    static func measure(_ view: some View, width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width, alignment: .leading))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        return height
    }

    /// The width a block takes on one line.
    @MainActor
    static func idealWidth(_ view: some View) -> CGFloat {
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.proposedSize = .unspecified
        var width: CGFloat = 0
        renderer.render { size, _ in width = size.width }
        return width
    }
}

/// One unbreakable piece of a column: a heading, an ingredient line, a step or a note paragraph.
struct PrintBlock: Identifiable {
    enum Kind {
        case sectionTitle(String)
        case groupTitle(String)
        case ingredient(amount: String?, text: String)
        case step(number: Int, text: String)
        case paragraph(String)
    }

    let id: Int
    let kind: Kind

    var isHeading: Bool {
        switch kind {
        case .sectionTitle, .groupTitle: true
        default: false
        }
    }

    static func ingredients(of recipe: ExportRecipe) -> [PrintBlock] {
        guard !recipe.ingredients.isEmpty else { return [] }
        var kinds: [Kind] = [.sectionTitle("Ingredients")]
        for group in recipe.ingredientGroups {
            if let name = group.name { kinds.append(.groupTitle(name)) }
            kinds += group.ingredients.map { .ingredient(amount: $0.amount, text: $0.description) }
        }
        return kinds.enumerated().map { PrintBlock(id: $0.offset, kind: $0.element) }
    }

    static func steps(of recipe: ExportRecipe) -> [PrintBlock] {
        guard !recipe.steps.isEmpty else { return [] }
        let kinds: [Kind] = [.sectionTitle("Steps")] + recipe.steps.enumerated().map { .step(number: $0.offset + 1, text: $0.element) }
        return kinds.enumerated().map { PrintBlock(id: 1_000 + $0.offset, kind: $0.element) }
    }

    /// The notes, a paragraph a block.
    static func notes(of recipe: ExportRecipe) -> [PrintBlock] {
        guard let notes = recipe.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else { return [] }
        let paragraphs = notes.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let kinds: [Kind] = [.sectionTitle("Notes")] + paragraphs.map { .paragraph($0) }
        return kinds.enumerated().map { PrintBlock(id: 100_000 + $0.offset, kind: $0.element) }
    }

    @ViewBuilder
    var view: some View {
        switch kind {
        case let .sectionTitle(title):
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .padding(.top, 2)
        case let .groupTitle(title):
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        case let .ingredient(amount, text):
            if let amount {
                Text("\(Text(amount).fontWeight(.semibold)) \(text)")
                    .font(.system(size: 10.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(text)
                    .font(.system(size: 10.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .step(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 10.5, weight: .bold))
                    .monospacedDigit()
                    .frame(width: 16, alignment: .trailing)
                Text(text)
                    .font(.system(size: 10.5))
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .paragraph(text):
            Text(text)
                .font(.system(size: 10.5))
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Title, source, meta line and cover, at the top of the first page.
struct PrintHeader: View {
    let recipe: ExportRecipe
    let cover: UIImage?
    /// The text width.
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipe.title)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            if let line = recipe.sourceLine, !line.isEmpty {
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let url = recipe.sourceURL {
                Text(url.absoluteString)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let meta = recipe.metaLine {
                Text(meta)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.top, 2)
            }
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: 210)
                    .clipShape(.rect(cornerRadius: 6))
                    .padding(.top, 8)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// One printed page: the header on the first, the two columns, what runs full width under them,
/// and the footer.
struct PrintPage: View {
    let recipe: ExportRecipe
    let cover: UIImage?
    let layout: RecipePDFRenderer.Layout
    let page: RecipePDFRenderer.Page
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pageNumber == 1 {
                PrintHeader(recipe: recipe, cover: cover, width: layout.textWidth)
                    .padding(.bottom, RecipePDFRenderer.sectionGap)
            }
            let hasColumns = !page.ingredients.isEmpty || !page.steps.isEmpty
            if hasColumns {
                HStack(alignment: .top, spacing: RecipePDFRenderer.columnGap) {
                    column(page.ingredients, width: layout.ingredientsWidth)
                    column(page.steps, width: layout.stepsWidth)
                }
            }
            if !page.below.isEmpty {
                column(page.below, width: layout.textWidth)
                    .padding(.top, hasColumns ? RecipePDFRenderer.sectionGap : 0)
            }
            Spacer(minLength: 0)
            HStack {
                Text(recipe.title)
                    .lineLimit(1)
                Spacer()
                Text("Page \(pageNumber) of \(pageCount)")
                    .monospacedDigit()
            }
            .font(.system(size: 8.5))
            .foregroundStyle(.secondary)
            .frame(height: RecipePDFRenderer.footerHeight, alignment: .bottom)
        }
        .padding(RecipePDFRenderer.margin)
        .frame(width: layout.paper.size.width, height: layout.paper.size.height, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    private func column(_ blocks: [PrintBlock], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RecipePDFRenderer.blockSpacing) {
            ForEach(blocks) { block in
                block.view
            }
        }
        .frame(width: width, alignment: .topLeading)
    }
}
