import Foundation
@testable import Capture

/// The private review report the page harness writes (`Docs/Fixtures/Private/Review`, gitignored):
/// per book and per page, what the pipeline read, with the full text for Caleb's review. Never
/// committed: it holds the books' text.
struct PageReport {
    struct Book {
        var slug: String
        var photos: Int
        var isbn: String?
        var readings: [PageReading] = []
        /// Each photo read alone, before stitching.
        var singles: [PageReading] = []
        /// Review reasons per stitched reading (by its first file), per recipe.
        var reviews: [String: [[ReviewReason]]] = [:]
        var modelNotes: [String] = []
        /// The punchlist read off the book's contents pages.
        var contents: BookContents?
    }

    var usesModel: Bool
    var books: [Book] = []
    var blurred: [PrivatePageTests.BlurCheck] = []

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try markdown().write(to: url, atomically: true, encoding: .utf8)
    }

    func markdown() -> String {
        var out: [String] = []
        let date = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime])
        out.append("# Page review, Phase 2 slice 2")
        out.append("")
        out.append("*Private. Written by `PrivatePageTests` (Packages/Capture) on \(date); \(usesModel ? "deterministic pass plus the on-device model (RECIPE_CODEX_PAGE_MODEL=1)" : "deterministic pass only"). It holds the books' text and stays in `Docs/Fixtures/Private/Review` (gitignored). The committed manifest is `Packages/Capture/Tests/CaptureTests/Fixtures/private-pages.json`.*")
        out.append("")

        // Summary.
        out.append("## Summary")
        out.append("")
        out.append("| Book | ISBN read | Photos | Recipe pages | Recipes | Stitched | Not recipes | Forced review | Other review | Median s/page | Slowest s |")
        out.append("|---|---|---|---|---|---|---|---|---|---|---|")
        var allTimes: [Double] = []
        for book in books {
            let times = book.singles.flatMap(\.durations).map(\.seconds)
            allTimes += times
            let recipePages = book.singles.filter { $0.kind == .recipe }.count
            let recipes = book.readings.reduce(0) { $0 + $1.recipes.count }
            let stitched = book.readings.filter { $0.files.count > 1 }.map { $0.files.joined(separator: "+") }
            let kinds = Dictionary(grouping: book.singles.filter { $0.kind != .recipe }, by: \.kind).map { "\($0.value.count) \($0.key.rawValue)" }.sorted()
            let reasons = book.reviews.values.flatMap { $0 }
            let forced = reasons.filter { $0.contains(.firstRecipeOfBook) || $0.contains(.unseenLayout) }.count
            let other = reasons.filter { !$0.isEmpty && !$0.contains(.firstRecipeOfBook) && !$0.contains(.unseenLayout) }.count
            out.append("| \(book.slug) | \(book.isbn ?? "—") | \(book.photos) (1 barcode) | \(recipePages) | \(recipes) | \(stitched.isEmpty ? "—" : stitched.joined(separator: ", ")) | \(kinds.joined(separator: ", ")) | \(forced) | \(other) | \(Self.format(Self.median(times))) | \(Self.format(times.max() ?? 0)) |")
        }
        out.append("")
        let sorted = allTimes.sorted()
        out.append("Timing over \(sorted.count) photos (gate, read and structure; full-size HEIC on this Mac): median \(Self.format(Self.median(sorted))) s, mean \(Self.format(sorted.reduce(0, +) / Double(max(1, sorted.count)))) s, slowest \(Self.format(sorted.last ?? 0)) s; the first photo read (\(Self.format(books.first?.singles.first?.durations.first?.seconds ?? 0)) s) includes loading Vision's models.")
        out.append("")

        // Review reasons.
        out.append("## Why review would be asked for")
        out.append("")
        out.append("Simulated per book in capture order: the first recipe and each new layout signature are forced, and confirming a review adds its layout to the book's confirmed ones (02 Flow B step 5).")
        out.append("")
        out.append("| Book | Reading | Recipe | Signature | Reasons |")
        out.append("|---|---|---|---|---|")
        for book in books {
            for reading in book.readings where reading.kind == .recipe {
                for (index, recipe) in reading.recipes.enumerated() {
                    let reasons = book.reviews[reading.files[0]]?[safe: index] ?? []
                    out.append("| \(book.slug) | \(reading.files.joined(separator: " + ")) | \(recipe.title.isEmpty ? "(untitled)" : recipe.title) | `\(recipe.layoutSignature)` | \(reasons.isEmpty ? "none: saved straight to the library" : reasons.map(\.label).joined(separator: "; ")) |")
                }
            }
        }
        out.append("")

        // Gate.
        out.append("## Quality gate")
        out.append("")
        out.append("Sharp at sharpness ≥ \(Int(PageQualityGate().minimumSharpness)); Clean the lens at smudge ≥ \(PageQualityGate().smudgeThreshold).")
        out.append("")
        out.append("| Photo | Reading | Sharpness | Smudge |")
        out.append("|---|---|---|---|")
        for book in books {
            for single in book.singles {
                if let quality = single.quality.first ?? nil {
                    out.append("| \(book.slug)/\(single.files[0]) | \(quality.quality.label) | \(Int(quality.sharpness)) | \(String(format: "%.3f", quality.smudge)) |")
                }
            }
        }
        for check in blurred {
            out.append("| \(check.label) (made in memory) | \(check.reading.quality.label) | \(Int(check.reading.sharpness)) | \(String(format: "%.3f", check.reading.smudge)) |")
        }
        out.append("")

        // Model.
        if usesModel {
            out.append("## On-device model")
            out.append("")
            for book in books {
                for note in book.modelNotes { out.append("- \(book.slug): \(note)") }
            }
            out.append("")
        }

        // Contents.
        out.append("## Contents pages")
        out.append("")
        out.append("Each book's contents photos read and combined in capture order (`ContentsReader`), as Build the Recipe List reads them.")
        for book in books {
            guard let contents = book.contents else { continue }
            out.append("")
            out.append("### \(book.slug): \(contents.sections.count) chapters, \(contents.entries.count) entries, \(contents.pagedEntryCount) with a page\(contents.isOverview ? " (chapters only)" : "")")
            for section in contents.sections {
                out.append("")
                out.append("- **\(section.title.isEmpty ? "(untitled)" : section.title)**\(section.page.map { ", p. \($0)" } ?? "") · course \(ChapterCourse.course(forChapter: section.title) ?? "none")")
                for entry in section.entries {
                    out.append("  - \(entry.title)\(entry.page.map { ", p. \($0)" } ?? ", no page")")
                }
            }
        }
        out.append("")

        // Pages.
        out.append("## Pages")
        for book in books {
            out.append("")
            out.append("### \(book.slug) (ISBN \(book.isbn ?? "not read"))")
            for single in book.singles {
                out.append("")
                out.append(contentsOf: page(single, book: book))
            }
        }
        out.append("")
        return out.joined(separator: "\n")
    }

    private func page(_ single: PageReading, book: Book) -> [String] {
        var out: [String] = []
        let file = single.files[0]
        out.append("#### \(book.slug) / \(file)")
        out.append("")
        let quality = single.quality.first ?? nil
        let blocks = single.blocks
        let byKind = Dictionary(grouping: blocks, by: \.kind).map { "\($0.value.count) \($0.key.rawValue)" }.sorted().joined(separator: ", ")
        let byRole = Dictionary(grouping: blocks, by: { $0.role?.rawValue ?? "unassigned" }).map { "\($0.value.count) \($0.key)" }.sorted().joined(separator: ", ")
        out.append("- **\(single.kind.rawValue)**\(single.isContinuation ? ", continues the page before" : "")\(single.reason.map { ": \($0)" } ?? "")")
        out.append("- Gate: \(quality.map { "\($0.quality.label) (sharpness \(Int($0.sharpness)), smudge \(String(format: "%.3f", $0.smudge)))" } ?? "—") · read in \(Self.format(single.durations.first?.seconds ?? 0)) s · page number: \(single.pageNumber.map(String.init) ?? "none read") · OCR confidence \(String(format: "%.2f", single.ocrConfidence))")
        out.append("- Blocks: \(blocks.count) (\(byKind)); roles: \(byRole)")

        // The stitched reading this photo opens, or the one it joined.
        if let reading = book.readings.first(where: { $0.files.first == file }), reading.kind == .recipe {
            if reading.files.count > 1 {
                out.append("- Stitched over \(reading.files.joined(separator: " + ")) (pages \(reading.pageNumbers.map { $0.map(String.init) ?? "?" }.joined(separator: ", ")))")
            }
            for (index, recipe) in reading.recipes.enumerated() {
                let reasons = book.reviews[file]?[safe: index] ?? []
                out.append("")
                out.append(contentsOf: Self.recipe(recipe, number: index + 1, of: reading.recipes.count, reasons: reasons, blocks: reading.blocks))
            }
        } else if let reading = book.readings.first(where: { $0.files.dropFirst().contains(file) }) {
            out.append("- Read into \(reading.files[0])'s recipe (stitched).")
        }

        out.append("")
        out.append("<details><summary>Blocks in reading order</summary>")
        out.append("")
        for block in blocks {
            let text = block.kind == .photo ? "(picture)" : block.text
            out.append("- \(block.id). \(block.role?.rawValue ?? "unassigned") · \(block.kind.rawValue) · \(block.rect) · \(String(format: "c%.2f", block.confidence)): \(text)")
        }
        out.append("")
        out.append("</details>")
        return out
    }

    private static func recipe(_ recipe: PageRecipe, number: Int, of total: Int, reasons: [ReviewReason], blocks: [PageBlock]) -> [String] {
        var out: [String] = []
        let heading = total > 1 ? "Recipe \(number) of \(total)" : "Recipe"
        out.append("**\(heading): \(recipe.title.isEmpty ? "(untitled)" : recipe.title)**")
        out.append("")
        let confidence = recipe.confidence
        out.append("- \(recipe.ingredients.count) ingredients (\(recipe.unparsedIngredientCount) unparsed), \(recipe.steps.count) steps, \(recipe.notes.count) notes; yield: \(recipe.yield ?? "none"); method: \(recipe.method.rawValue)")
        out.append("- Confidence: OCR \(String(format: "%.2f", confidence.ocr)), parser \(String(format: "%.2f", confidence.parser)), structure \(String(format: "%.2f", confidence.structure))\(confidence.model.map { ", model \(String(format: "%.2f", $0))" } ?? ""), combined \(String(format: "%.2f", confidence.combined))")
        out.append("- Layout signature: `\(recipe.layoutSignature)`")
        out.append("- Review: \(reasons.isEmpty ? "not asked for" : reasons.map(\.label).joined(separator: "; "))\(recipe.stepCountDisagrees ? " (step count disagrees)" : "")\(recipe.unassignedBlocks.isEmpty ? "" : " (unassigned blocks \(recipe.unassignedBlocks.map(String.init).joined(separator: ", ")))")")
        if recipe.startsMidStep || recipe.endsMidStep {
            out.append("- \(recipe.startsMidStep ? "Starts mid-step" : "")\(recipe.startsMidStep && recipe.endsMidStep ? "; " : "")\(recipe.endsMidStep ? "ends mid-step (continues overleaf)" : "")")
        }
        if let headnote = recipe.headnote {
            out.append("")
            out.append("*Headnote:* \(headnote.replacingOccurrences(of: "\n\n", with: " ¶ "))")
        }
        out.append("")
        out.append("*Ingredients:*")
        out.append("")
        var group: String?
        for ingredient in recipe.ingredients {
            if ingredient.group != group, let name = ingredient.group {
                out.append("- **\(name)**")
            }
            group = ingredient.group
            let parsed = ingredient.parsed
            let reading = [parsed.quantity.map { "\($0)" }, parsed.unit.map { "\($0.rawValue)" }, parsed.item.isEmpty ? nil : "“\(parsed.item)”", parsed.preparation.map { "prep “\($0)”" }, parsed.note.map { "note “\($0)”" }].compactMap { $0 }.joined(separator: " · ")
            out.append("- \(ingredient.text)  — \(reading)\(ingredient.isUnparsed ? " **(unparsed)**" : "")")
        }
        out.append("")
        out.append("*Steps:*")
        out.append("")
        for (index, step) in recipe.steps.enumerated() {
            let photo = step.photo.map { " [step photo: block \($0) \(blocks[safe: $0]?.rect.description ?? "")]" } ?? ""
            out.append("\(index + 1). \(step.number.map { "(printed \($0)) " } ?? "")\(step.text)\(photo)")
        }
        for note in recipe.notes {
            out.append("")
            out.append("*Note:* \(note)")
        }
        if !recipe.crossReferences.isEmpty {
            out.append("")
            out.append("*Cross-references:* " + recipe.crossReferences.map { "\($0.kind.rawValue) p. \($0.pages.map(String.init).joined(separator: ", "))\($0.target.map { " (\($0))" } ?? "") — “\($0.phrase)”" }.joined(separator: "; "))
        }
        return out
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    static func format(_ value: Double) -> String { String(format: "%.2f", value) }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
