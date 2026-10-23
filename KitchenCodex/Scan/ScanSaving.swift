import Capture
import CoreImage
import Foundation
import ImageIO
import RecipeModel
import SwiftData
import UIKit

// Saving a scanned recipe (03 §3.3's scanned state, 02 Flow B step 8): through `RecipeDraft` as a
// web import saves, then the page scans with their regions, the provenance, and any printed photo
// the cook made a step photo or the cover.

/// A page photo upright, as stored and as review shows it.
enum ScanImage {
    /// The longest side a page scan is stored at: a photographed page's body text stays legible
    /// when View Page zooms in, at about a megabyte a page.
    nonisolated static let storedPixelSize = 3_000
    nonisolated static let storedQuality: CGFloat = 0.8

    /// The page upright: the photo with its EXIF orientation applied, turned by the quarter turns
    /// the reader read it at (`PageReading.quarterTurns`), so the regions' rects, which are in the
    /// turned frame, match it. A stored scan is upright already.
    @concurrent
    nonisolated static func upright(_ page: ReviewPage, maxPixelSize: Int = storedPixelSize) async -> CGImage? {
        if let data = page.imageData {
            return downsample(data, maxPixelSize: maxPixelSize)
        }
        guard let url = page.fileURL, let image = try? PageImage.load(contentsOf: url, maxPixelSize: maxPixelSize) else { return nil }
        return turned(image, quarterTurns: page.quarterTurns)
    }

    /// `image` turned a quarter counterclockwise `quarterTurns` times, as the reader turned it
    /// (orientation `.left` for one, `.right` for three).
    nonisolated static func turned(_ image: CGImage, quarterTurns: Int) -> CGImage {
        let orientation: CGImagePropertyOrientation
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1: orientation = .left
        case 2: orientation = .down
        case 3: orientation = .right
        default: return image
        }
        let turned = CIImage(cgImage: image).oriented(orientation)
        return CIContext().createCGImage(turned, from: turned.extent) ?? image
    }

    nonisolated static func jpeg(_ image: CGImage, quality: CGFloat = storedQuality) -> Data? {
        UIImage(cgImage: image).jpegData(compressionQuality: quality)
    }

    /// A region of the upright page, for a printed photo made a step photo or the cover.
    nonisolated static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let pixels = CGRect(x: rect.minX * CGFloat(image.width), y: rect.minY * CGFloat(image.height),
                            width: rect.width * CGFloat(image.width), height: rect.height * CGFloat(image.height)).integral
        return image.cropping(to: pixels.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)))
    }

    nonisolated static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}

extension ScanReviewModel {
    /// A copy with recipe `index` replaced, for saving one part of a split: the pages and regions
    /// are the same, the review on screen untouched.
    func replacing(_ index: Int, with recipe: ReviewRecipe) -> ScanReviewModel {
        var recipes = recipes
        recipes[index] = recipe
        let copy = ScanReviewModel(pages: pages, regions: regions, recipes: recipes)
        copy.current = index
        copy.storedCover = storedCover
        return copy
    }

    /// The regions of `page` as `RecipeImage.regions` keeps them for recipe `index`: its own and
    /// the page's furniture, not the other recipe's, each with the item it became.
    func scanRegions(page: Int, recipe index: Int) -> ScanRegions {
        let recipe = recipes[index]
        let own = regions.filter { $0.page == page && ($0.recipe == nil || $0.recipe == index || recipes.count == 1) }
        func position(of id: Int, in items: [ReviewItem]) -> Int? { items.firstIndex { $0.regions.contains(id) } }
        let mapped = own.map { region -> ScanRegion in
            var role = region.role
            var item: Int?
            if region.isPhoto {
                role = recipe.cover == region.id ? .cover : (recipe.stepPhotos[region.id] != nil ? .stepPhoto : (region.role == .ignore ? .ignore : nil))
                item = recipe.stepPhotos[region.id].flatMap { step in recipe.steps.firstIndex { $0.id == step } }
            } else if region.recipe == index || recipes.count == 1 {
                switch role {
                case .title: item = recipe.title?.regions.contains(region.id) == true ? 0 : nil
                case .yield: item = recipe.yield?.regions.contains(region.id) == true ? 0 : nil
                case .headnote: item = position(of: region.id, in: recipe.headnote)
                case .ingredient, .ingredientGroup: item = position(of: region.id, in: recipe.ingredients)
                case .step: item = position(of: region.id, in: recipe.steps)
                case .note: item = position(of: region.id, in: recipe.notes)
                default: item = nil
                }
            }
            return ScanRegion(
                kind: region.kind, role: role?.rawValue,
                x: region.rect.minX, y: region.rect.minY, width: region.rect.width, height: region.rect.height,
                // The printed lines, one per line, so review can read them back as lines.
                text: region.lines.joined(separator: "\n"),
                confidence: region.confidence, item: item
            )
        }
        return ScanRegions(layoutSignature: recipe.layoutSignature.isEmpty ? nil : recipe.layoutSignature, pageNumber: pages.first { $0.id == page }?.pageNumber, regions: mapped)
    }

    /// Every region of `page`, for a page kept as a page scan with no recipe.
    func scanRegions(page: Int) -> ScanRegions {
        let mapped = regions.filter { $0.page == page }.map { region in
            ScanRegion(kind: region.kind, role: region.role?.rawValue, x: region.rect.minX, y: region.rect.minY,
                       width: region.rect.width, height: region.rect.height, text: region.lines.joined(separator: "\n"),
                       confidence: region.confidence)
        }
        return ScanRegions(pageNumber: pages.first { $0.id == page }?.pageNumber, regions: mapped)
    }
}

/// Saves what scan review holds.
@MainActor
enum ScanSaving {
    /// The upright JPEG of each page, encoded once and shared by the recipes on it (each recipe has
    /// its own `RecipeImage` with the same bytes and its own regions, ux-notes row 60).
    final class PageImages {
        var images: [String: CGImage] = [:]
        var jpegs: [String: Data] = [:]

        /// One photo across the scan's readings: its file (a page's id counts within its reading).
        private func key(_ page: ReviewPage) -> String {
            page.fileURL.map { "\($0.path)#\(page.quarterTurns)" } ?? "stored-\(page.id)"
        }

        func image(_ page: ReviewPage) async -> CGImage? {
            if let image = images[key(page)] { return image }
            let image = await ScanImage.upright(page)
            images[key(page)] = image
            return image
        }

        func jpeg(_ page: ReviewPage) async -> Data? {
            if let data = jpegs[key(page)] { return data }
            if let stored = page.imageData {
                jpegs[key(page)] = stored
                return stored
            }
            guard let image = await image(page) else { return nil }
            let data = await Self.encode(image)
            jpegs[key(page)] = data
            return data
        }

        @concurrent
        nonisolated private static func encode(_ image: CGImage) async -> Data? {
            ScanImage.jpeg(image)
        }
    }

    /// The source line's "Bouchon, p. 12" or "pp. 12–13", or "a photo" with no book.
    static func pagesText(book: Book?, pages: [Int]) -> String {
        guard let book else { return "a photo" }
        guard let first = pages.min() else { return book.displayTitle }
        if let last = pages.max(), last != first { return "\(book.displayTitle), pp. \(first)–\(last)" }
        return "\(book.displayTitle), p. \(first)"
    }

    /// Saves recipe `index` of `model` as a new recipe. `reviewed` is whether the cook confirmed it
    /// in review; unreviewed, it is "Accepted automatically" and asks for a look only on low
    /// confidence (`reasons` beyond the book's first recipe and a new layout). Its cross-reference
    /// cards' answers are applied unless `appliesPointers` is false (the book session applies its
    /// own rule once a capture's recipes are all saved).
    ///
    /// A recipe the cook split in review (04 §5.1 "Sub-recipes on one page") saves as its parent,
    /// which keeps the page scans, and its components, linked from it; the parent is returned.
    @discardableResult
    static func saveNew(_ model: ScanReviewModel, recipe index: Int, book: Book?, reviewed: Bool, images: PageImages, appliesPointers: Bool = true, in context: ModelContext) async -> Recipe {
        guard let split = RecipeSplitting.split(model.recipes[index]) else {
            return await saveOne(model, recipe: index, book: book, reviewed: reviewed, images: images, appliesPointers: appliesPointers, in: context)
        }
        let parent = await saveOne(model.replacing(index, with: split.parent), recipe: index, book: book, reviewed: reviewed, images: images, appliesPointers: appliesPointers, in: context)
        var components: [Recipe] = []
        for component in split.components {
            let saved = await saveOne(model.replacing(index, with: component), recipe: index, book: book, reviewed: reviewed, images: images,
                                      attachesPages: false, appliesPointers: appliesPointers, changeSummary: "Split from “\(parent.title)”", in: context)
            components.append(saved)
        }
        RecipeSplitting.link(parent, to: components, in: context)
        return parent
    }

    /// One recipe of the review saved: with the page scans and their regions unless
    /// `attachesPages` is false (a component split off a parent that has them).
    private static func saveOne(_ model: ScanReviewModel, recipe index: Int, book: Book?, reviewed: Bool, images: PageImages, attachesPages: Bool = true,
                                appliesPointers: Bool, changeSummary: String? = nil, in context: ModelContext) async -> Recipe {
        let review = model.recipes[index]
        let pageNumbers = model.pages.compactMap(\.pageNumber)
        var imported = review.imported
        imported.author = book?.author.isEmpty == false ? book?.author : nil
        var draft = RecipeDraft(imported: imported)
        draft.course = review.course
        draft.changeSummary = changeSummary ?? ("Scanned from \(pagesText(book: book, pages: pageNumbers))" + (reviewed ? "" : " · Accepted automatically"))
        if let cover = review.cover, let photo = await coverPhoto(region: cover, in: model, images: images) {
            draft.photo = photo
        }
        let recipe = draft.saveImport(imported, in: context)

        recipe.book = book
        recipe.pageNumber = pageNumbers.first
        recipe.extractionConfidence = review.confidence.combined
        if let source = recipe.source {
            source.captureMethod = .photo
            source.siteName = nil
            source.firstPage = pageNumbers.min()
            source.lastPage = pageNumbers.count > 1 ? pageNumbers.max() : nil
            source.reviewedAt = reviewed ? .now : nil
        }
        if let version = recipe.currentVersion {
            version.reviewReasons = review.reasons.map(\.rawValue)
            version.needsReview = !reviewed && review.reasons.contains { !ScanGate.forcing.contains($0) }
        }
        if attachesPages {
            await attachPageScans(model, recipe: index, to: recipe, book: book, images: images, in: context)
        }
        await attachStepPhotos(model, recipe: index, to: recipe, images: images, in: context)
        if reviewed, attachesPages, let book, !review.layoutSignature.isEmpty, !book.reviewedLayouts.contains(review.layoutSignature) {
            book.reviewedLayouts.append(review.layoutSignature)
        }
        try? context.save()
        if appliesPointers {
            CrossReferenceLinking.apply(review.pointers, to: recipe, in: book, context: context)
        }
        return recipe
    }

    /// Saves a review of a recipe already in the library (detail → More → Review Scan): a new
    /// version when the content changed, the regions as the cook left them, step photos and the
    /// cover as assigned, and the review recorded.
    ///
    /// Split in review, the recipe keeps the parent's items and its components are saved beside it,
    /// linked from it.
    static func saveReview(_ model: ScanReviewModel, of recipe: Recipe, images: PageImages, in context: ModelContext) async {
        if let split = RecipeSplitting.split(model.recipes[model.current]) {
            let index = model.current
            await saveReview(model.replacing(index, with: split.parent), of: recipe, images: images, in: context)
            var components: [Recipe] = []
            for component in split.components {
                components.append(await saveOne(model.replacing(index, with: component), recipe: index, book: recipe.book, reviewed: true, images: images,
                                                attachesPages: false, appliesPointers: true, changeSummary: "Split from “\(recipe.title)”", in: context))
            }
            RecipeSplitting.link(recipe, to: components, in: context)
            return
        }
        let index = model.current
        let review = model.recipes[index]
        let original = RecipeDraft(recipe: recipe)
        var draft = RecipeDraft(imported: review.imported)
        draft.course = review.course
        draft.changeSummary = "Reviewed against the page"
        if let cover = review.cover, cover != model.storedCover, let photo = await coverPhoto(region: cover, in: model, images: images) {
            draft.photo = photo
        }
        draft.save(to: recipe, comparedWith: original, in: context)
        if let headnote = review.imported.headnote { recipe.headnote = headnote }

        // The regions as the cook left them, on the page scans already stored.
        let scans = recipe.pageScans
        for (page, scan) in scans.enumerated() {
            scan.regions = try? model.scanRegions(page: model.pages[min(page, model.pages.count - 1)].id, recipe: index).encoded()
        }
        // Source step photos are the page's printed photos; they follow the review's assignments.
        if let version = recipe.currentVersion {
            for step in version.sortedSteps {
                for photo in step.sortedPhotos where photo.cookSession == nil {
                    context.delete(photo)
                }
            }
        }
        await attachStepPhotos(model, recipe: index, to: recipe, images: images, in: context)
        recipe.markReviewed(in: context)
        recipe.source?.reviewedAt = .now
        // Its punchlist entry is reviewed (02 Flow C step 7).
        if let entry = recipe.bookEntry { entry.status = .reviewed }
        if let book = recipe.book, !review.layoutSignature.isEmpty, !book.reviewedLayouts.contains(review.layoutSignature) {
            book.reviewedLayouts.append(review.layoutSignature)
        }
        try? context.save()
        CrossReferenceLinking.apply(review.pointers, to: recipe, in: recipe.book, context: context)
    }

    /// A recipe read again with another page joined to it (ux-notes row 100): the stitched reading
    /// saved as a new version of `recipe`, the cook's version kept as history, its page scans
    /// replaced by the joined pages', its pages and page number as the pages now say.
    static func saveAgain(_ model: ScanReviewModel, recipe index: Int, into recipe: Recipe, book: Book?, images: PageImages, changeSummary: String, in context: ModelContext) async {
        let review = model.recipes[index]
        let pageNumbers = model.pages.compactMap(\.pageNumber)
        let original = RecipeDraft(recipe: recipe)
        var draft = RecipeDraft(imported: review.imported)
        draft.title = recipe.title
        draft.course = recipe.course
        draft.changeSummary = changeSummary
        draft.save(to: recipe, comparedWith: original, in: context)
        if let headnote = review.imported.headnote, recipe.headnote.isEmpty { recipe.headnote = headnote }
        for scan in recipe.pageScans { context.delete(scan) }
        recipe.pageNumber = pageNumbers.first ?? recipe.pageNumber
        recipe.extractionConfidence = review.confidence.combined
        if let source = recipe.source {
            source.firstPage = pageNumbers.min() ?? source.firstPage
            source.lastPage = pageNumbers.count > 1 ? pageNumbers.max() : nil
        }
        await attachPageScans(model, recipe: index, to: recipe, book: book, images: images, in: context)
        try? context.save()
    }

    /// Keeps a page that is not a recipe (a contents, index or Sources page, a photo plate) on its
    /// book as a page scan, with its regions and no recipe.
    static func keepPageScan(_ model: ScanReviewModel, kind: PageKind, book: Book, images: PageImages, fallbackPage: Int? = nil, in context: ModelContext) async {
        for page in model.pages {
            guard let data = await images.jpeg(page) else { continue }
            let scan = RecipeImage(role: .pageScan, imageData: data)
            context.insert(scan)
            scan.pageNumber = page.pageNumber ?? fallbackPage
            scan.pageKind = ScanPageKind(kind)
            scan.regions = try? model.scanRegions(page: page.id).encoded()
            scan.book = book
        }
        try? context.save()
    }

    private static func attachPageScans(_ model: ScanReviewModel, recipe index: Int, to recipe: Recipe, book: Book?, images: PageImages, in context: ModelContext) async {
        for page in model.pages {
            guard let data = await images.jpeg(page) else { continue }
            let scan = RecipeImage(role: .pageScan, imageData: data)
            context.insert(scan)
            scan.caption = "Page"
            scan.pageNumber = page.pageNumber
            scan.pageKind = .recipe
            scan.regions = try? model.scanRegions(page: page.id, recipe: index).encoded()
            scan.book = book
            scan.recipe = recipe
        }
    }

    /// Photo-mode captures (04 §5.1 "Printed photos", ux-notes row 62): each cropped to the page's
    /// outline and the printed picture's bounds when they are found (row 86), kept on the recipe
    /// as a cover candidate, the first made the cover when the recipe has none, and the best by
    /// Vision's aesthetic score made the cover once there are several (`CoverSelection`). No
    /// question asked.
    @discardableResult
    static func attachCoverCandidates(_ urls: [URL], to recipe: Recipe, in context: ModelContext) async -> [RecipeImage] {
        guard !urls.isEmpty else { return [] }
        var attached: [RecipeImage] = []
        for url in urls {
            guard let file = try? Data(contentsOf: url) else { continue }
            var candidate = await croppedCandidate(file)
            if candidate == nil { candidate = await ImageProcessing.jpeg(from: file, maxPixelSize: 2_400, quality: 0.85) }
            guard let photo = candidate else { continue }
            let image = RecipeImage(role: .photo, imageData: photo)
            context.insert(image)
            image.recipe = recipe
            if recipe.coverImageData == nil, let cover = await ImageProcessing.jpeg(from: photo, maxPixelSize: 900, quality: 0.8) {
                image.caption = "Cover"
                recipe.coverImageData = cover
            } else {
                image.caption = RecipeDraft.coverCandidateCaption
            }
            attached.append(image)
        }
        try? context.save()
        await CoverSelection.choose(for: recipe, in: context)
        return attached
    }

    /// The photo cropped to the page and its picture (ux-notes row 86), as a 2,400-pixel JPEG; nil
    /// when no page outline is found, so the photo stays as taken.
    @concurrent
    nonisolated private static func croppedCandidate(_ data: Data) async -> Data? {
        guard let image = try? PageImage.load(data: data, maxPixelSize: 2_400), let cropped = await PageCleanup.cropToPicture(image) else { return nil }
        return ScanImage.jpeg(cropped, quality: 0.85)
    }

    /// Printed photos the cook made step photos, cropped from the page and attached to their steps.
    private static func attachStepPhotos(_ model: ScanReviewModel, recipe index: Int, to recipe: Recipe, images: PageImages, in context: ModelContext) async {
        let review = model.recipes[index]
        guard !review.stepPhotos.isEmpty, let steps = recipe.currentVersion?.sortedSteps else { return }
        for (regionID, stepID) in review.stepPhotos.sorted(by: { $0.key < $1.key }) {
            guard let stepIndex = review.steps.firstIndex(where: { $0.id == stepID }), steps.indices.contains(stepIndex),
                  let data = await crop(region: regionID, in: model, images: images, maxPixelSize: 1_600) else { continue }
            let photo = RecipeImage(role: .stepPhoto, imageData: data)
            context.insert(photo)
            photo.step = steps[stepIndex]
            photo.recipe = recipe
        }
    }

    private static func coverPhoto(region: Int, in model: ScanReviewModel, images: PageImages) async -> RecipeDraft.PhotoChange? {
        guard let photo = await crop(region: region, in: model, images: images, maxPixelSize: 2_400),
              let cover = await ImageProcessing.jpeg(from: photo, maxPixelSize: 900, quality: 0.8) else { return nil }
        return .replaced(photo: photo, cover: cover)
    }

    private static func crop(region id: Int, in model: ScanReviewModel, images: PageImages, maxPixelSize: CGFloat) async -> Data? {
        guard let region = model.region(id), let page = model.pages.first(where: { $0.id == region.page }),
              let image = await images.image(page), let cropped = ScanImage.crop(image, to: region.rect),
              let data = ScanImage.jpeg(cropped, quality: 0.85) else { return nil }
        return await ImageProcessing.jpeg(from: data, maxPixelSize: maxPixelSize, quality: 0.85)
    }
}

extension ScanPageKind {
    /// What a page that is not a recipe is kept as.
    init(_ kind: PageKind) {
        switch kind {
        case .recipe: self = .recipe
        case .contents: self = .contents
        case .index: self = .index
        case .sources: self = .sources
        case .photo: self = .photo
        case .prose: self = .reference
        case .blank, .unreadable: self = .other
        }
    }
}

extension Recipe {
    /// The recipe's page scans in page order.
    var pageScans: [RecipeImage] {
        (images ?? []).filter { $0.role == .pageScan }.sorted { ($0.pageNumber ?? .max, $0.createdAt) < ($1.pageNumber ?? .max, $1.createdAt) }
    }

    /// Scanned from a page: it has a page scan.
    var isScanned: Bool { images?.contains { $0.role == .pageScan } == true }
}
