import Capture
import SwiftUI
import UIKit

/// A recipe laid out for paper (US Letter): title, cover and meta on the first page, then
/// ingredients and steps side by side in two columns that continue onto later pages, with the
/// title and page numbers in the footer. Made with SwiftUI and drawn into a PDF by `ImageRenderer`.
enum RecipePDFRenderer {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 54
    static let footerHeight: CGFloat = 22
    static let columnGap: CGFloat = 28
    static let blockSpacing: CGFloat = 7

    static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    static var ingredientsWidth: CGFloat { (contentWidth - columnGap) * 0.38 }
    static var stepsWidth: CGFloat { contentWidth - columnGap - ingredientsWidth }
    /// Height for the columns on a page without the header.
    static var columnHeight: CGFloat { pageSize.height - margin * 2 - footerHeight }

    /// The PDF's bytes. The cover is decoded at print size off the main actor; layout and drawing
    /// happen on it, as `ImageRenderer` requires.
    static func pdf(for recipe: ExportRecipe, coverData: Data?) async -> Data {
        var cover: UIImage?
        if let coverData {
            cover = await ImageProcessing.thumbnail(from: coverData, maxPixelSize: 1_400)
        }
        return render(recipe, cover: cover)
    }

    @MainActor
    static func render(_ recipe: ExportRecipe, cover: UIImage?) -> Data {
        let pages = paginate(recipe, cover: cover)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, [
                  kCGPDFContextTitle: recipe.title,
                  kCGPDFContextCreator: "Recipe Codex",
              ] as CFDictionary) else { return Data() }

        for (index, page) in pages.enumerated() {
            let view = PrintPage(
                recipe: recipe,
                cover: cover,
                page: page,
                pageNumber: index + 1,
                pageCount: pages.count
            )
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    // MARK: - Pagination

    struct Page {
        var ingredients: [PrintBlock] = []
        var steps: [PrintBlock] = []
    }

    /// Fills each column block by block, measuring every block at its column's width. A heading is
    /// never left at the foot of a column without the block after it.
    @MainActor
    static func paginate(_ recipe: ExportRecipe, cover: UIImage?) -> [Page] {
        let firstPageColumns = columnHeight - measure(PrintHeader(recipe: recipe, cover: cover), width: contentWidth) - 20
        func capacity(_ page: Int) -> CGFloat { page == 0 ? max(firstPageColumns, 120) : columnHeight }

        func flow(_ blocks: [PrintBlock], width: CGFloat) -> [[PrintBlock]] {
            var columns: [[PrintBlock]] = [[]]
            var used: CGFloat = 0
            let heights = blocks.map { measure($0.view, width: width) }
            for (index, block) in blocks.enumerated() {
                var needed = heights[index]
                // Keep a heading with what follows it.
                if block.isHeading, index + 1 < blocks.count { needed += blockSpacing + heights[index + 1] }
                let spacing = columns[columns.count - 1].isEmpty ? 0 : blockSpacing
                if used + spacing + needed > capacity(columns.count - 1), !columns[columns.count - 1].isEmpty {
                    columns.append([])
                    used = 0
                }
                let gap = columns[columns.count - 1].isEmpty ? 0 : blockSpacing
                columns[columns.count - 1].append(block)
                used += gap + heights[index]
            }
            return columns
        }

        let ingredientColumns = flow(PrintBlock.ingredients(of: recipe), width: ingredientsWidth)
        let stepColumns = flow(PrintBlock.steps(of: recipe), width: stepsWidth)
        let count = max(ingredientColumns.count, stepColumns.count, 1)
        return (0..<count).map { index in
            Page(
                ingredients: index < ingredientColumns.count ? ingredientColumns[index] : [],
                steps: index < stepColumns.count ? stepColumns[index] : []
            )
        }
    }

    @MainActor
    static func measure(_ view: some View, width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width, alignment: .leading))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        return height
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
        var kinds: [Kind] = []
        if !recipe.steps.isEmpty {
            kinds.append(.sectionTitle("Steps"))
            kinds += recipe.steps.enumerated().map { .step(number: $0.offset + 1, text: $0.element) }
        }
        if let notes = recipe.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            kinds.append(.sectionTitle("Notes"))
            kinds += notes.components(separatedBy: "\n\n").map { .paragraph($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { if case let .paragraph(text) = $0 { !text.isEmpty } else { true } }
        }
        return kinds.enumerated().map { PrintBlock(id: 1_000 + $0.offset, kind: $0.element) }
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
                    .frame(width: RecipePDFRenderer.contentWidth, height: 210)
                    .clipShape(.rect(cornerRadius: 6))
                    .padding(.top, 8)
            }
        }
        .frame(width: RecipePDFRenderer.contentWidth, alignment: .leading)
    }
}

/// One printed page: the header on the first, two columns, and the footer.
struct PrintPage: View {
    let recipe: ExportRecipe
    let cover: UIImage?
    let page: RecipePDFRenderer.Page
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pageNumber == 1 {
                PrintHeader(recipe: recipe, cover: cover)
                    .padding(.bottom, 20)
            }
            HStack(alignment: .top, spacing: RecipePDFRenderer.columnGap) {
                column(page.ingredients, width: RecipePDFRenderer.ingredientsWidth)
                column(page.steps, width: RecipePDFRenderer.stepsWidth)
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
        .frame(width: RecipePDFRenderer.pageSize.width, height: RecipePDFRenderer.pageSize.height, alignment: .topLeading)
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
