import Foundation

/// Joins the readings of consecutive photos when a recipe runs over a page turn or a spread
/// (04 §2 Phase 2: multi-page stitching). A page with no title that carries ingredients or steps
/// continues the recipe before it: its ingredients and groups follow the earlier ones, and its steps
/// follow the earlier steps. When the earlier page's last step stops mid-sentence and the later
/// page's first step runs on (no indent, number or run-in head), they are one printed paragraph
/// broken by the page and are rejoined; no other steps are merged or split.
public enum PageStitcher {
    /// Stitches a run of readings in capture order. Readings that are not recipes, or that open
    /// with a title, start a new reading.
    public static func stitch(_ readings: [PageReading]) -> [PageReading] {
        var result: [PageReading] = []
        for reading in readings {
            if let last = result.last, canContinue(last, with: reading) {
                result[result.count - 1] = join(last, reading)
            } else {
                result.append(reading)
            }
        }
        return result
    }

    /// `next` continues `previous`: it opens without a title and with a recipe's content, and the
    /// page before ends in a recipe.
    public static func canContinue(_ previous: PageReading, with next: PageReading) -> Bool {
        guard previous.kind == .recipe, next.kind == .recipe, next.isContinuation,
              let opening = next.recipes.first, !(opening.ingredients.isEmpty && opening.steps.isEmpty),
              let ending = previous.recipes.last else { return false }
        // A printed "continued" line at the first page's foot or the next page's head is the cue
        // (ux-notes row 131), and so is a page of method alone on the book's very next page. A
        // page with an ingredient list of its own is a recipe whose title didn't read, never a
        // continuation by adjacency.
        if ending.continuesOverPage || opening.continuesFromPage { return true }
        if opening.ingredients.isEmpty, let last = previous.pageNumbers.last ?? nil, let first = next.pageNumbers.first ?? nil, first == last + 1 { return true }
        // A recipe that closed with its yield ("MAKES 2 TO 4 SERVINGS") and a complete last step
        // has ended; a page after it with no title is something else (a continuation photographed
        // out of order, a variation box).
        if ending.yield != nil, !ending.endsMidStep, !opening.startsMidStep, opening.ingredients.isEmpty { return false }
        return true
    }

    static func join(_ previous: PageReading, _ next: PageReading) -> PageReading {
        var reading = previous
        let fileOffset = previous.files.count
        let blockOffset = previous.blocks.count
        reading.files += next.files
        reading.pageNumbers += next.pageNumbers
        reading.quality += next.quality
        reading.durations += next.durations
        reading.quarterTurns += next.quarterTurns
        reading.blocks += next.blocks.map { block in
            var copy = block
            copy.id += blockOffset
            copy.file += fileOffset
            // The later page's first recipe is the one it continues; the rest follow it.
            copy.recipe = copy.recipe.map { $0 == 0 ? previous.recipes.count - 1 : previous.recipes.count + $0 - 1 }
            return copy
        }
        let lineCount = Double(previous.blocks.flatMap(\.lines).count + next.blocks.flatMap(\.lines).count)
        if lineCount > 0 {
            let total = previous.ocrConfidence * Double(previous.blocks.flatMap(\.lines).count) + next.ocrConfidence * Double(next.blocks.flatMap(\.lines).count)
            reading.ocrConfidence = total / lineCount
        }

        var recipe = previous.recipes[previous.recipes.count - 1]
        var opening = next.recipes[0]
        // Block indices in the later page's recipe point into the joined block list.
        opening.ingredients = opening.ingredients.map { var copy = $0; copy.block += blockOffset; return copy }
        opening.steps = opening.steps.map { var copy = $0; copy.blocks = copy.blocks.map { $0 + blockOffset }; copy.photo = copy.photo.map { $0 + blockOffset }; return copy }
        opening.unassignedBlocks = opening.unassignedBlocks.map { $0 + blockOffset }

        recipe.ingredients += opening.ingredients
        var steps = opening.steps
        if recipe.endsMidStep, opening.startsMidStep, let first = steps.first, !recipe.steps.isEmpty {
            // One paragraph broken by the page turn.
            let last = recipe.steps.count - 1
            recipe.steps[last].text = PageText.join([recipe.steps[last].text, first.text])
            recipe.steps[last].blocks += first.blocks
            recipe.steps[last].photo = recipe.steps[last].photo ?? first.photo
            steps.removeFirst()
        }
        recipe.steps += steps
        recipe.notes += opening.notes
        recipe.crossReferences += opening.crossReferences.filter { reference in !recipe.crossReferences.contains(reference) }
        recipe.unassignedBlocks += opening.unassignedBlocks
        recipe.yield = recipe.yield ?? opening.yield
        if recipe.headnote == nil { recipe.headnote = opening.headnote }
        recipe.endsMidStep = opening.endsMidStep
        recipe.continuesOverPage = opening.continuesOverPage
        recipe.stepCountDisagrees = recipe.stepCountDisagrees || opening.stepCountDisagrees
        // Confidence over both pages, weighted by what each contributed.
        let weightA = Double(max(1, recipe.ingredients.count - opening.ingredients.count + recipe.steps.count - steps.count))
        let weightB = Double(max(1, opening.ingredients.count + opening.steps.count))
        func mix(_ a: Double, _ b: Double) -> Double { (a * weightA + b * weightB) / (weightA + weightB) }
        let parsed = recipe.ingredients.isEmpty ? 0 : Double(recipe.ingredients.count { !$0.isUnparsed }) / Double(recipe.ingredients.count)
        recipe.confidence = PageConfidence(
            ocr: mix(recipe.confidence.ocr, opening.confidence.ocr),
            parser: parsed,
            structure: recipe.confidence.structure,
            model: recipe.confidence.model
        )
        reading.recipes[reading.recipes.count - 1] = recipe
        // The later page's own recipes after its continuation stay separate.
        reading.recipes += next.recipes.dropFirst().map { later in
            var copy = later
            copy.ingredients = copy.ingredients.map { var item = $0; item.block += blockOffset; return item }
            copy.steps = copy.steps.map { var step = $0; step.blocks = step.blocks.map { $0 + blockOffset }; step.photo = step.photo.map { $0 + blockOffset }; return step }
            copy.unassignedBlocks = copy.unassignedBlocks.map { $0 + blockOffset }
            return copy
        }
        return reading
    }
}
