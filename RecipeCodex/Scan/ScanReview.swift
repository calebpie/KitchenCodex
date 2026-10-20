import Capture
import CoreGraphics
import Foundation
import Observation
import RecipeModel

// Scan review's model (03 §3.6): the pages and their regions, the structured recipe each region
// fed, reassigning a region, flashing an item's source, and Undo. Built from a fresh reading
// (`PageReading`) or from a recipe's stored page scans (`ScanRegions`), so an auto-accepted scan
// can be reviewed later from detail's More.

/// What a region is in the recipe, as review labels and reassigns it. The raw values are Capture's
/// `PageBlock.Role` raw values, which `ScanRegion.role` stores, plus `cover`: a printed photo the
/// cook made the recipe's cover (ux-notes row 62).
enum RegionRole: String, CaseIterable, Identifiable {
    case title, yield, time, headnote, ingredient, ingredientGroup, step, note, stepPhoto, cover
    case furniture, crossReference, ignore

    var id: Self { self }

    /// The label on the region (03 §3.6: labels, not colour alone).
    var label: String {
        switch self {
        case .title: "Title"
        case .yield: "Yield"
        case .time: "Time"
        case .headnote: "Headnote"
        case .ingredient: "Ingredients"
        case .ingredientGroup: "Group"
        case .step: "Step"
        case .note: "Note"
        case .stepPhoto: "Step Photo"
        case .cover: "Cover"
        case .furniture: "Page"
        case .crossReference: "Reference"
        case .ignore: "Ignored"
        }
    }

    /// What the cook can make a text region: the floating control's choices (03 §3.6).
    static let textChoices: [RegionRole] = [.title, .yield, .ingredient, .step, .headnote, .note, .ignore]
    /// What a printed photo can become (ux-notes row 62): nothing unless the cook taps it.
    static let photoChoices: [RegionRole] = [.stepPhoto, .cover, .ignore]
}

/// One block on a page, as review shows it.
struct ReviewRegion: Identifiable, Equatable {
    /// The block's place in the reading (its `PageBlock.id`).
    let id: Int
    /// Which page of the reading it is on.
    let page: Int
    /// What the reader saw (`PageBlock.Kind` raw value).
    let kind: String
    var role: RegionRole?
    /// Unit page coordinates, top-left origin, upright.
    let rect: CGRect
    /// The printed lines.
    let lines: [String]
    let confidence: Double
    /// The recipe on the page it belongs to; nil for the page's furniture and anything no recipe
    /// claimed.
    var recipe: Int?

    var isPhoto: Bool { kind == PageBlock.Kind.photo.rawValue }
    var text: String { PageRegionText.paragraph(lines) }
}

/// One part of the structured recipe: a line, a step, a paragraph of headnote, with the regions
/// it came from.
struct ReviewItem: Identifiable, Equatable {
    let id: UUID
    var text: String
    var regions: [Int]
    /// The ingredient group heading over it.
    var group: String?

    init(text: String, regions: [Int], group: String? = nil) {
        id = UUID()
        self.text = text
        self.regions = regions
        self.group = group
    }

    /// Reading order: the first region it came from; one read by the model comes last.
    var order: Int { regions.min() ?? .max }
}

/// One recipe on the page as the cook reviews it.
struct ReviewRecipe: Equatable {
    var title: ReviewItem?
    var yield: ReviewItem?
    var headnote: [ReviewItem] = []
    var ingredients: [ReviewItem] = []
    var steps: [ReviewItem] = []
    var notes: [ReviewItem] = []
    /// Printed photos the cook made step photos: the photo region and the step item.
    var stepPhotos: [Int: ReviewItem.ID] = [:]
    /// The printed photo the cook made the cover.
    var cover: Int?
    /// Skip, offered for a page scanned on its own (ux-notes row 60).
    var isSkipped = false

    var prepTime: Duration?
    var cookTime: Duration?
    var totalTime: Duration?
    var layoutSignature: String = ""
    var confidence = PageConfidence(ocr: 0, parser: 0, structure: 0)
    var method: ImportMethod = .pageText
    var reasons: [ReviewReason] = []

    var displayTitle: String { title?.text.isEmpty == false ? title!.text : "Untitled Recipe" }

    /// Every item, for flashing and finding.
    var allItems: [ReviewItem] {
        [title, yield].compactMap(\.self) + headnote + ingredients + steps + notes
    }

    /// The recipe as the importer's draft, which saves through `RecipeDraft` as a web import does.
    /// Steps are the printed paragraphs, as read or as the cook edited them; none is split or
    /// merged.
    var imported: ImportedRecipe {
        var groups: [Int: String] = [:]
        var previous: String?
        for (index, item) in ingredients.enumerated() where item.group != previous {
            if let group = item.group { groups[index] = group }
            previous = item.group
        }
        var recipe = ImportedRecipe(
            title: title?.text ?? "",
            ingredients: ingredients.map(\.text),
            steps: steps.map { ImportedStep(text: $0.text.replacingOccurrences(of: "\n", with: " ")) },
            yield: yield?.text,
            prepTime: prepTime,
            cookTime: cookTime,
            totalTime: totalTime,
            ingredientGroups: groups,
            method: method,
            confidence: confidence.combined
        )
        let headnoteText = headnote.map(\.text).joined(separator: "\n\n")
        recipe.headnote = headnoteText.isEmpty ? nil : headnoteText
        recipe.notes = notes.map(\.text)
        return recipe
    }
}

/// One page of a scan in review: where its image is, and what was read off it.
struct ReviewPage: Identifiable, Equatable {
    let id: Int
    /// The photo as chosen (a fresh scan), read and turned upright when shown and saved.
    var fileURL: URL?
    /// The stored, upright page scan (a review from detail).
    var imageData: Data?
    var quarterTurns: Int
    var pageNumber: Int?
    var quality: PageQuality?
}

/// Scan review's state for one reading: one photo, or several stitched, and the recipes on them.
@Observable
final class ScanReviewModel {
    var pages: [ReviewPage]
    var regions: [ReviewRegion]
    var recipes: [ReviewRecipe]
    /// The recipe on screen when the page holds several.
    var current = 0
    /// The region the floating control assigns.
    var selectedRegion: Int?
    /// Regions picked with the lasso on iPad, assigned together.
    var lassoed: [Int] = []
    /// The item being edited in place.
    var editingItem: ReviewItem.ID?
    /// Regions flashing because their item was tapped.
    var flashing: Set<Int> = []
    private(set) var undoStack: [Snapshot] = []
    /// A review of a stored scan: the region that was the cover when it opened.
    var storedCover: Int?
    /// Printed photos the structurer found beside a step: the step Step Photo offers first.
    var candidateSteps: [Int: ReviewItem.ID] = [:]
    /// Whether the cook changed anything, so Rescan and Cancel ask first.
    var hasChanges: Bool { !undoStack.isEmpty }

    struct Snapshot: Equatable {
        var regions: [ReviewRegion]
        var recipes: [ReviewRecipe]
    }

    init(pages: [ReviewPage], regions: [ReviewRegion], recipes: [ReviewRecipe]) {
        self.pages = pages
        self.regions = regions
        self.recipes = recipes
    }

    var recipe: ReviewRecipe {
        get { recipes[current] }
        set { recipes[current] = newValue }
    }

    func region(_ id: Int) -> ReviewRegion? { regions.first { $0.id == id } }

    // MARK: - Undo

    /// Records the state before a change.
    func checkpoint() {
        undoStack.append(Snapshot(regions: regions, recipes: recipes))
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        regions = last.regions
        recipes = last.recipes
        selectedRegion = nil
        editingItem = nil
    }

    // MARK: - Flashing

    /// Tapping an item flashes the regions it came from.
    func flash(_ item: ReviewItem) {
        flashing = Set(item.regions)
    }

    // MARK: - Reassigning

    /// Makes `id` the `role` in the recipe on screen (03 §3.6): whatever it fed before loses it,
    /// and it becomes the title, the yield, ingredient lines, one step, a paragraph of headnote or
    /// of notes in reading order, a step photo of `step`, the cover, or nothing.
    func assign(_ ids: [Int], to role: RegionRole, step: ReviewItem.ID? = nil) {
        guard !ids.isEmpty else { return }
        checkpoint()
        for id in ids.sorted() {
            apply(id, role: role, step: step)
        }
        selectedRegion = nil
        lassoed = []
    }

    private func apply(_ id: Int, role: RegionRole, step: ReviewItem.ID?) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        removeEverywhere(id)
        let region = regions[index]
        regions[index].role = role == .ignore ? .ignore : role
        regions[index].recipe = role == .ignore ? nil : current
        var recipe = recipes[current]
        switch role {
        case .title:
            // A line next to the title in reading order joins it; anywhere else it replaces it.
            if let title = recipe.title, !title.regions.isEmpty, adjoins(id, title.regions) {
                let ids = (title.regions + [id]).sorted()
                recipe.title = ReviewItem(text: titleText(ids), regions: ids)
            } else {
                if let old = recipe.title { unassign(old.regions) }
                recipe.title = ReviewItem(text: titleText([id]), regions: [id])
            }
        case .yield:
            if let old = recipe.yield { unassign(old.regions) }
            recipe.yield = ReviewItem(text: PageRegionText.yield(region.lines), regions: [id])
        case .ingredient, .ingredientGroup:
            let lines = PageRegionText.ingredientLines(region.lines)
            let position = recipe.ingredients.firstIndex { $0.order > id } ?? recipe.ingredients.count
            let group = position > 0 ? recipe.ingredients[position - 1].group : recipe.ingredients.first?.group
            recipe.ingredients.insert(contentsOf: lines.map { ReviewItem(text: $0, regions: [id], group: group) }, at: position)
            regions[index].role = .ingredient
        case .step:
            insert(ReviewItem(text: region.text, regions: [id]), into: &recipe.steps)
        case .headnote:
            insert(ReviewItem(text: region.text, regions: [id]), into: &recipe.headnote)
        case .note:
            insert(ReviewItem(text: region.text, regions: [id]), into: &recipe.notes)
        case .stepPhoto:
            if let step = step ?? recipe.steps.first?.id {
                recipe.stepPhotos[id] = step
            } else {
                regions[index].role = nil
            }
        case .cover:
            if let old = recipe.cover, old != id, let oldIndex = regions.firstIndex(where: { $0.id == old }) {
                regions[oldIndex].role = nil
            }
            recipe.cover = id
        case .time, .furniture, .crossReference, .ignore:
            break
        }
        recipes[current] = recipe
    }

    private func insert(_ item: ReviewItem, into items: inout [ReviewItem]) {
        let position = items.firstIndex { $0.order > item.order } ?? items.count
        items.insert(item, at: position)
    }

    /// Whether `id` sits next to `ids` among the page's text regions.
    private func adjoins(_ id: Int, _ ids: [Int]) -> Bool {
        let text = regions.filter { !$0.isPhoto && $0.role != .furniture }.map(\.id).sorted()
        guard let position = text.firstIndex(of: id) else { return false }
        let neighbours = [position - 1, position + 1].filter(text.indices.contains).map { text[$0] }
        return neighbours.contains { ids.contains($0) }
    }

    private func titleText(_ ids: [Int]) -> String {
        PageRegionText.title(ids.compactMap(region).flatMap(\.lines))
    }

    /// Regions an item no longer uses go back to unassigned.
    private func unassign(_ ids: [Int]) {
        for id in ids {
            if let index = regions.firstIndex(where: { $0.id == id }) { regions[index].role = nil }
        }
    }

    /// Takes `id` out of every recipe: every item it fed goes (03 §3.6: the region now feeds one
    /// thing), and so does a step photo or cover it was.
    private func removeEverywhere(_ id: Int) {
        for index in recipes.indices {
            var recipe = recipes[index]
            if recipe.title?.regions.contains(id) == true {
                let rest = recipe.title!.regions.filter { $0 != id }
                recipe.title = rest.isEmpty ? nil : ReviewItem(text: titleText(rest), regions: rest)
            }
            if recipe.yield?.regions.contains(id) == true { recipe.yield = nil }
            let removedSteps = Set(recipe.steps.filter { $0.regions.contains(id) }.map(\.id))
            recipe.headnote.removeAll { $0.regions.contains(id) }
            recipe.ingredients.removeAll { $0.regions.contains(id) }
            recipe.steps.removeAll { $0.regions.contains(id) }
            recipe.notes.removeAll { $0.regions.contains(id) }
            recipe.stepPhotos[id] = nil
            recipe.stepPhotos = recipe.stepPhotos.filter { !removedSteps.contains($0.value) }
            if recipe.cover == id { recipe.cover = nil }
            recipes[index] = recipe
        }
    }

    // MARK: - Editing

    /// The cook's own wording for an item, as read from the page (a fix OCR got wrong).
    func edit(_ id: ReviewItem.ID, text: String) {
        var recipe = recipes[current]
        func update(_ items: inout [ReviewItem]) -> Bool {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].text != text else { return false }
            checkpoint()
            items[index].text = text
            return true
        }
        if recipe.title?.id == id, recipe.title?.text != text {
            checkpoint()
            recipe.title?.text = text
        } else if recipe.yield?.id == id, recipe.yield?.text != text {
            checkpoint()
            recipe.yield?.text = text
        } else if !update(&recipe.headnote), !update(&recipe.ingredients), !update(&recipe.steps) {
            _ = update(&recipe.notes)
        }
        recipes[current] = recipe
    }

    /// Removes an item and leaves its regions unassigned.
    func remove(_ item: ReviewItem) {
        checkpoint()
        for id in item.regions where !(recipe.allItems.contains { $0.id != item.id && $0.regions.contains(id) }) {
            if let index = regions.firstIndex(where: { $0.id == id }) { regions[index].role = nil }
        }
        var recipe = recipes[current]
        if recipe.title?.id == item.id { recipe.title = nil }
        if recipe.yield?.id == item.id { recipe.yield = nil }
        recipe.headnote.removeAll { $0.id == item.id }
        recipe.ingredients.removeAll { $0.id == item.id }
        recipe.steps.removeAll { $0.id == item.id }
        recipe.notes.removeAll { $0.id == item.id }
        recipe.stepPhotos = recipe.stepPhotos.filter { $0.value != item.id }
        recipes[current] = recipe
    }

    func toggleSkip() {
        checkpoint()
        recipes[current].isSkipped.toggle()
    }

    // MARK: - What the page pane shows

    /// The role a region shows: its own, or for a printed photo, what the cook made it.
    func shownRole(of region: ReviewRegion) -> RegionRole? {
        if region.isPhoto {
            if recipes.contains(where: { $0.cover == region.id }) { return .cover }
            if recipes.contains(where: { $0.stepPhotos[region.id] != nil }) { return .stepPhoto }
            return region.role == .ignore ? .ignore : nil
        }
        return region.role
    }

    /// Whether the region belongs to the recipe on screen (or to none): the others are dimmed.
    func isInCurrentRecipe(_ region: ReviewRegion) -> Bool {
        region.recipe == nil || region.recipe == current || recipes.count == 1
    }

    /// The step number a printed photo is attached to in the recipe on screen.
    func stepNumber(forPhoto id: Int) -> Int? {
        guard let step = recipe.stepPhotos[id] else { return nil }
        return recipe.steps.firstIndex { $0.id == step }.map { $0 + 1 }
    }
}

// MARK: - Building a review

extension ScanReviewModel {
    /// A review of a fresh reading: its pages (`urls` holds the chosen photos by file name), its
    /// blocks as regions and its recipes as items. Printed photos start unassigned (ux-notes row 62),
    /// with the structurer's step beside each as the one Step Photo offers first.
    convenience init(reading: PageReading, urls: [URL]) {
        let pages = reading.files.enumerated().map { index, file in
            ReviewPage(
                id: index,
                fileURL: urls.first { $0.lastPathComponent == file },
                quarterTurns: reading.quarterTurns.indices.contains(index) ? reading.quarterTurns[index] : 0,
                pageNumber: reading.pageNumbers.indices.contains(index) ? reading.pageNumbers[index] : nil,
                quality: reading.quality.indices.contains(index) ? reading.quality[index]?.quality : nil
            )
        }
        var regions = reading.blocks.map { block in
            ReviewRegion(
                id: block.id, page: block.file, kind: block.kind.rawValue,
                role: block.kind == .photo && block.role == .stepPhoto ? nil : block.role.flatMap { RegionRole(rawValue: $0.rawValue) },
                rect: CGRect(x: block.rect.x, y: block.rect.y, width: block.rect.width, height: block.rect.height),
                lines: block.lines.map(\.text), confidence: block.confidence, recipe: block.recipe
            )
        }
        var candidates: [Int: ReviewItem.ID] = [:]
        let recipes = reading.recipes.enumerated().map { index, recipe -> ReviewRecipe in
            func regionIDs(_ role: PageBlock.Role) -> [Int] {
                reading.blocks.filter { $0.role == role && $0.recipe == index }.map(\.id)
            }
            /// A yield set at the head of the headnote ("MAKES 2 CUPS / …") came from the headnote's block.
            func yieldRegions(_ yield: String) -> [Int] {
                let own = regionIDs(.yield)
                guard own.isEmpty else { return own }
                let key = yield.lowercased().prefix(12)
                return reading.blocks.filter { $0.recipe == index && $0.text.lowercased().contains(key) }.map(\.id).prefix(1).map(\.self)
            }
            var review = ReviewRecipe()
            if !recipe.title.isEmpty { review.title = ReviewItem(text: recipe.title, regions: regionIDs(.title)) }
            if let yield = recipe.yield { review.yield = ReviewItem(text: yield, regions: yieldRegions(yield)) }
            if let headnote = recipe.headnote { review.headnote = [ReviewItem(text: headnote, regions: regionIDs(.headnote))] }
            review.ingredients = recipe.ingredients.map { ReviewItem(text: $0.text, regions: $0.block >= 0 ? [$0.block] : [], group: $0.group) }
            review.steps = recipe.steps.map { ReviewItem(text: $0.text, regions: $0.blocks) }
            let notes = regionIDs(.note)
            review.notes = recipe.notes.enumerated().map { offset, note in
                ReviewItem(text: note, regions: notes.count == recipe.notes.count ? [notes[offset]] : (offset == 0 ? notes : []))
            }
            for (step, item) in zip(recipe.steps, review.steps) {
                if let photo = step.photo { candidates[photo] = item.id }
            }
            review.prepTime = recipe.prepTime
            review.cookTime = recipe.cookTime
            review.totalTime = recipe.totalTime
            review.layoutSignature = recipe.layoutSignature
            review.confidence = recipe.confidence
            review.method = recipe.method
            return review
        }
        // A printed photo the structurer put beside a step still belongs to that recipe.
        for index in regions.indices where regions[index].isPhoto && regions[index].recipe == nil {
            if let step = candidates[regions[index].id], let owner = recipes.firstIndex(where: { $0.steps.contains { $0.id == step } }) {
                regions[index].recipe = owner
            }
        }
        self.init(pages: pages, regions: regions, recipes: recipes)
        candidateSteps = candidates
    }

    /// A review of a recipe's stored page scans (detail → More → Review Scan): the regions as
    /// saved, and the recipe's current version as the items, matched to the regions by the item
    /// each became. Nil for a recipe with no page scan.
    convenience init?(recipe: Recipe) {
        let scans = recipe.pageScans
        guard !scans.isEmpty, let version = recipe.currentVersion else { return nil }
        var pages: [ReviewPage] = []
        var regions: [ReviewRegion] = []
        var signature = ""
        for (index, scan) in scans.enumerated() {
            let stored = ScanRegions.decoded(from: scan.regions)
            signature = signature.isEmpty ? (stored?.layoutSignature ?? "") : signature
            pages.append(ReviewPage(id: index, imageData: scan.imageData, quarterTurns: 0, pageNumber: scan.pageNumber ?? stored?.pageNumber))
            for (offset, region) in (stored?.regions ?? []).enumerated() {
                let role = region.role.flatMap(RegionRole.init(rawValue:))
                regions.append(ReviewRegion(
                    id: index * 10_000 + offset, page: index, kind: region.kind, role: role,
                    rect: CGRect(x: region.x, y: region.y, width: region.width, height: region.height),
                    lines: region.text.components(separatedBy: "\n"), confidence: region.confidence,
                    recipe: role == nil || role == .furniture || role == .ignore ? nil : 0
                ))
            }
        }
        let stored = scans.flatMap { ScanRegions.decoded(from: $0.regions)?.regions ?? [] }
        /// The regions of `role`, with the item each became, in reading order.
        func items(_ role: RegionRole) -> [(id: Int, item: Int?)] {
            zip(regions, stored).filter { $0.0.role == role }.map { ($0.0.id, $0.1.item) }
        }
        /// The regions an item at `index` came from: those that became it, or, for a region that
        /// became several lines, the nearest before it.
        func sources(_ role: RegionRole, index: Int, count: Int) -> [Int] {
            let all = items(role)
            let exact = all.filter { $0.item == index }.map(\.id)
            if !exact.isEmpty { return exact }
            return all.filter { ($0.item ?? .max) <= index }.max { ($0.item ?? 0) < ($1.item ?? 0) }.map { [$0.id] } ?? []
        }
        var review = ReviewRecipe()
        review.title = ReviewItem(text: recipe.title, regions: items(.title).map(\.id))
        if !version.yieldText.isEmpty || version.servings != nil {
            review.yield = ReviewItem(text: version.yieldText.isEmpty ? "Serves \(version.servings!)" : version.yieldText, regions: items(.yield).map(\.id))
        }
        if !recipe.headnote.isEmpty { review.headnote = [ReviewItem(text: recipe.headnote, regions: items(.headnote).map(\.id))] }
        let ingredients = version.sortedIngredients
        review.ingredients = ingredients.enumerated().map { index, ingredient in
            ReviewItem(text: ingredient.rawText, regions: sources(.ingredient, index: index, count: ingredients.count), group: ingredient.group)
        }
        let steps = version.sortedSteps
        review.steps = steps.enumerated().map { index, step in
            ReviewItem(text: step.text, regions: sources(.step, index: index, count: steps.count))
        }
        let notes = version.notes.components(separatedBy: "\n\n").filter { !$0.trimmed.isEmpty }
        review.notes = notes.enumerated().map { index, note in ReviewItem(text: note, regions: sources(.note, index: index, count: notes.count)) }
        for (id, item) in items(.stepPhoto) {
            if let item, review.steps.indices.contains(item) { review.stepPhotos[id] = review.steps[item].id }
        }
        review.cover = items(.cover).first?.id
        review.prepTime = version.prepMinutes.map { .seconds($0 * 60) }
        review.cookTime = version.cookMinutes.map { .seconds($0 * 60) }
        review.totalTime = version.totalMinutes.map { .seconds($0 * 60) }
        review.layoutSignature = signature
        review.confidence = PageConfidence(ocr: 0, parser: 0, structure: 0)
        review.reasons = version.reviewReasons.compactMap(ReviewReason.init(rawValue:))
        self.init(pages: pages, regions: regions, recipes: [review])
        storedCover = review.cover
    }
}
