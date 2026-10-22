import Capture
import Foundation
import ImageIO
import RecipeModel
import SwiftData
import UIKit

// Shared by the app's Import from Web sheet and the Share Extension (compiled into both targets), so
// every import is saved the way manual entry saves: through `RecipeDraft`.

extension RecipeDraft {
    /// A draft prefilled from an import: one ingredient per line, steps separated by blank lines.
    init(imported: ImportedRecipe) {
        self.init()
        title = imported.title
        course = RecipeCourse.match(category: imported.category)
        servings = imported.servings.map(String.init) ?? ""
        yieldText = imported.yieldDescription ?? ""
        prepMinutes = imported.prepTime.map(Self.minutesText) ?? ""
        cookMinutes = imported.cookTime.map(Self.minutesText) ?? ""
        totalMinutes = imported.totalTime.map(Self.minutesText) ?? ""
        ingredientsText = Self.ingredientsText(imported.ingredients.enumerated().map { (imported.group(forIngredientAt: $0.offset), $0.element) })
        stepsText = imported.steps.map(\.text).joined(separator: "\n\n")
        notes = imported.notes.joined(separator: "\n\n")
    }

    private static func minutesText(_ duration: Duration) -> String {
        String((duration.components.seconds + 30) / 60)
    }

    /// Saves a new recipe from an import (or a manual entry started from a failed one), then records
    /// where it came from: the source line, the capture confidence and the review flag. Ingredient
    /// groups travel in the ingredients text as "Heading:" lines. A library export's categories
    /// become tags (see `tags(named:in:)`). `imported.method == nil` means the cook typed it in.
    /// Step photos the source shows are downloaded after the save and attached as they arrive (see
    /// `attachStepPhotos`).
    @discardableResult
    func saveImport(_ imported: ImportedRecipe, in context: ModelContext) -> Recipe {
        var draft = self
        if draft.changeSummary.trimmed.isEmpty {
            draft.changeSummary = imported.method == nil ? "Added by hand" : "Imported from \(imported.importedFrom ?? imported.sourceName)"
        }
        let recipe = draft.save(to: nil, comparedWith: RecipeDraft(), in: context)
        recipe.cuisine = recipe.cuisine ?? imported.cuisine
        recipe.isFavorite = imported.isFavorite
        if !imported.categories.isEmpty {
            recipe.tags = Self.tags(named: imported.categories, in: context)
        }
        if let headnote = imported.headnote?.trimmed, !headnote.isEmpty { recipe.headnote = headnote }
        if let created = imported.createdAt {
            recipe.createdAt = created
            recipe.currentVersion?.createdAt = created
        }

        let source = SourceInfo(url: imported.sourceURL, author: imported.author)
        source.siteName = imported.siteName ?? imported.sourceURL?.host()
        source.importedAt = .now
        // How it came in (04 §5.1 "Which book"); a scan sets its own after saving.
        switch imported.method {
        case .libraryFile?: source.captureMethod = .library
        case nil: source.captureMethod = .manual
        default: source.captureMethod = .web
        }
        context.insert(source)
        recipe.source = source

        if let version = recipe.currentVersion, imported.method != nil {
            version.captureConfidence = imported.confidence
            version.needsReview = imported.needsReview
        }
        try? context.save()

        if imported.stepImageCount > 0 {
            Task {
                let photos = await Self.stepPhotos(for: imported)
                Self.attachStepPhotos(photos, from: imported, to: recipe, in: context)
            }
        }
        return recipe
    }

    /// One tag per name: the library's tag of that name, ignoring case and accents, else a new one
    /// named as written. Paprika and Mela categories arrive this way, so "weeknight" from one recipe
    /// and "Weeknight" from the next share a tag.
    static func tags(named names: [String], in context: ModelContext) -> [Tag] {
        var existing = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        var result: [Tag] = []
        for name in names {
            let tag: Tag
            if let match = existing.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                tag = match
            } else {
                tag = Tag(name: name)
                context.insert(tag)
                existing.append(tag)
            }
            if !result.contains(where: { $0 === tag }) { result.append(tag) }
        }
        return result
    }

    /// Downloads and prepares the import's cover the way the editor prepares a picked photo. An
    /// embedded photo (Paprika, Mela) is used as is, without a download.
    static func coverPhoto(for imported: ImportedRecipe) async -> (change: PhotoChange, preview: UIImage?) {
        var source = imported.imageData
        if source == nil, let url = imported.imageURL {
            source = try? await WebPageFetcher().fetchImage(url, referrer: imported.sourceURL)
        }
        guard let data = source,
              let photo = await ImageProcessing.jpeg(from: data, maxPixelSize: 2_400, quality: 0.85),
              let cover = await ImageProcessing.jpeg(from: data, maxPixelSize: 900, quality: 0.8) else {
            return (.unchanged, nil)
        }
        return (.replaced(photo: photo, cover: cover), await ImageProcessing.thumbnail(from: cover, maxPixelSize: 900))
    }

    /// Step photos larger than this as downloaded are skipped.
    static let stepPhotoByteLimit = 15_000_000

    /// Downloads every step photo the import names, four at a time, with the page as referrer, and
    /// re-encodes each as JPEG with its longest side at most 1,600 px. Failures are left out.
    static func stepPhotos(for imported: ImportedRecipe) async -> [URL: Data] {
        let urls = Array(Set(imported.steps.compactMap(\.imageURL)))
        let referrer = imported.sourceURL
        let limit = stepPhotoByteLimit
        var photos: [URL: Data] = [:]
        await withTaskGroup(of: (URL, Data?).self) { group in
            var next = 0
            func enqueue() {
                guard next < urls.count else { return }
                let url = urls[next]
                next += 1
                group.addTask {
                    guard let data = try? await WebPageFetcher().fetchImage(url, referrer: referrer),
                          data.count <= limit else { return (url, nil) }
                    return (url, await ImageProcessing.jpeg(from: data, maxPixelSize: 1_600, quality: 0.82))
                }
            }
            for _ in 0..<4 { enqueue() }
            while let (url, data) = await group.next() {
                if let data { photos[url] = data }
                enqueue()
            }
        }
        return photos
    }

    /// Saves downloaded step photos as `.stepPhoto` images on the recipe's current steps, with no
    /// cook session (they came from the source). Each photo goes to the step whose text matches the
    /// imported step, or to the same position when the preview kept the number of steps.
    static func attachStepPhotos(_ photos: [URL: Data], from imported: ImportedRecipe, to recipe: Recipe, in context: ModelContext) {
        guard !photos.isEmpty, let version = recipe.currentVersion, recipe.modelContext != nil else { return }
        let steps = version.sortedSteps
        func key(_ text: String) -> String {
            text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        for (index, importedStep) in imported.steps.enumerated() {
            guard let url = importedStep.imageURL, let data = photos[url] else { continue }
            let target = steps.first { key($0.text) == key(importedStep.text) }
                ?? (steps.count == imported.steps.count ? steps[index] : nil)
            guard let target else { continue }
            let image = RecipeImage(role: .stepPhoto, imageData: data)
            context.insert(image)
            image.step = target
            image.recipe = recipe
        }
        try? context.save()
    }
}

extension ImportedReference {
    /// Saves an article read from the web as a Reference with its sections, its figures (ux-notes
    /// row 130) and its source (the link, the author and the site), kind article (02 §4.2). Shared
    /// by Import from Web and the Share Extension, as `saveImport` is for recipes. The figures are
    /// downloaded first, so the extension's save has them before it closes.
    @discardableResult
    func save(in context: ModelContext) async -> Reference {
        let photos = await Self.figurePhotos(for: self)
        let reference = Reference(title: title, author: author ?? "", kind: referenceKind)
        context.insert(reference)
        for (index, section) in sections.enumerated() {
            let stored = ReferenceSection(heading: section.heading, body: section.body, sortOrder: index)
            context.insert(stored)
            stored.reference = reference
        }
        // Each figure in reading order: the section it follows kept as its `pageNumber` (an article
        // has no pages), its caption from the page's alt text.
        let start = Date.now
        for (index, figure) in figures.enumerated() {
            guard let data = photos[index] else { continue }
            let image = RecipeImage(role: .photo, imageData: data)
            context.insert(image)
            image.caption = figure.caption
            image.pageNumber = figure.section
            image.createdAt = start.addingTimeInterval(Double(index) / 1_000)
            image.reference = reference
        }
        let source = SourceInfo(url: sourceURL, author: author)
        source.siteName = siteName ?? sourceURL?.host()?.replacingOccurrences(of: "www.", with: "")
        source.importedAt = .now
        source.captureMethod = .web
        context.insert(source)
        reference.source = source
        try? context.save()
        return reference
    }

    /// A figure smaller than this on its short side, once downloaded, is a decoration or a
    /// tracking image, left out as an icon is.
    static let figureMinimumSide = 200

    /// The figures as JPEG by their place in `figures`: downloaded four at a time with the article
    /// as referrer, each re-encoded with its longest side at most 1,600 px; one that fails, is too
    /// large, or is small once downloaded is left out.
    static func figurePhotos(for reference: ImportedReference) async -> [Int: Data] {
        let figures = reference.figures
        let referrer = reference.sourceURL
        let limit = RecipeDraft.stepPhotoByteLimit
        let minimum = figureMinimumSide
        var photos: [Int: Data] = [:]
        await withTaskGroup(of: (Int, Data?).self) { group in
            var next = 0
            func enqueue() {
                guard next < figures.count else { return }
                let index = next
                let url = figures[index].url
                next += 1
                group.addTask {
                    guard let data = try? await WebPageFetcher().fetchImage(url, referrer: referrer), data.count <= limit,
                          let size = Self.pixelSize(of: data), min(size.width, size.height) >= minimum else { return (index, nil) }
                    return (index, await ImageProcessing.jpeg(from: data, maxPixelSize: 1_600, quality: 0.82))
                }
            }
            for _ in 0..<4 { enqueue() }
            while let (index, data) = await group.next() {
                if let data { photos[index] = data }
                enqueue()
            }
        }
        return photos
    }

    /// An image's pixel size, read from its header without decoding it.
    nonisolated static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    /// A reference already saved from the same link (ux-notes row 112), so the preview can say so.
    func existing(in context: ModelContext) -> Reference? {
        guard let key = sourceURL.map(Self.linkKey) else { return nil }
        let references = (try? context.fetch(FetchDescriptor<Reference>())) ?? []
        return references.first { $0.source?.url.map(Self.linkKey) == key }
    }

    /// A link as two saves of one page share it: no fragment, no trailing slash, "www." gone.
    static func linkKey(_ url: URL) -> String {
        var text = url.absoluteString
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        while text.hasSuffix("/") { text.removeLast() }
        return text.replacingOccurrences(of: "://www.", with: "://").lowercased()
    }

    /// "4 sections · 9 photos": what the preview says the article holds.
    var contentsLine: String {
        let count = sections.count
        var parts = [count == 1 ? "1 section" : "\(count) sections"]
        if !figures.isEmpty { parts.append(figures.count == 1 ? "1 photo" : "\(figures.count) photos") }
        return parts.joined(separator: " · ")
    }

    /// The library's kind: a glossary is a chapter of its book.
    var referenceKind: ReferenceKind {
        switch kind {
        case .article: .article
        case .technique: .technique
        case .chapter, .glossary: .chapter
        }
    }

    /// "Serious Eats", or the host when the page names no site.
    var sourceName: String {
        siteName ?? sourceURL?.host()?.replacingOccurrences(of: "www.", with: "") ?? "the web"
    }
}

extension ImportedRecipe {
    /// "Serious Eats", or the host when the page names no site.
    var sourceName: String {
        siteName ?? sourceURL?.host()?.replacingOccurrences(of: "www.", with: "") ?? "the web"
    }

    /// The one-line status from 03 §3.4, saying how the recipe was found.
    var statusLine: String {
        switch method {
        case .jsonLD?, .microdata?:
            "Found a recipe on this page."
        case .pageText?:
            "No recipe data on this page, so it was read from the page text. Check it before you cook."
        case .model?:
            "No recipe data on this page, so Apple Intelligence read the page text. Check it before you cook."
        case .libraryFile?:
            "Imported from \(importedFrom ?? "another app")."
        case nil:
            "Couldn't read a recipe from this page. Add it by hand; the link is kept."
        }
    }

    /// An empty recipe that keeps the page's title and link, for "Add Manually Instead".
    static func manual(title: String, url: URL?) -> ImportedRecipe {
        ImportedRecipe(title: title, sourceURL: url, method: nil, confidence: 1)
    }
}

extension RecipeCourse {
    /// The standard course for a page's `recipeCategory` ("Main Course", "side-dish",
    /// "Dinner, Main Course, Poultry", "Desserts or Baked Goods"), if one fits: the first
    /// comma-separated part that names a course decides. Paprika and Mela categories arrive joined
    /// the same way, so "Weeknight, Dinner" is a Main; every one of them is also a tag.
    static func match(category: String?) -> String? {
        guard let category else { return nil }
        let table: [(course: String, words: [String])] = [
            ("Main", ["main", "mains", "main course", "main dish", "main-dish", "entree", "entrée", "entrees", "dinner", "lunch"]),
            ("Side", ["side", "sides", "side dish", "side-dish", "side dishes"]),
            ("Dessert", ["dessert", "desserts", "desserts or baked goods", "cake", "cookies", "pie"]),
            ("Starter", ["starter", "starters", "appetizer", "appetizers", "hors d'oeuvres", "first course"]),
            ("Soup", ["soup", "soups", "stew", "stews"]),
            ("Salad", ["salad", "salads"]),
            ("Breakfast", ["breakfast", "brunch"]),
            ("Bread", ["bread", "breads"]),
            ("Sauce", ["sauce", "sauces", "condiment", "condiments", "condiments and sauces", "sauces & condiments"]),
            ("Drink", ["drink", "drinks", "beverage", "beverages", "cocktail", "cocktails"]),
            ("Snack", ["snack", "snacks"]),
        ]
        let parts = category.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if let match = table.first(where: { $0.words.contains(part) }) { return match.course }
        }
        return nil
    }
}
