import Capture
import CoreGraphics
import Foundation
import RecipeModel
import SwiftData
import UIKit
import Vision

/// The cover among a recipe's cover candidates (phase2-plan "Slice 8": `CalculateImageAestheticsScoresRequest`
/// over a recipe's images chooses the cover; ux-notes row 86): Vision scores each photo the
/// session attached, and the best-scoring one that isn't a utility image (a receipt, a screenshot,
/// a page of text) becomes the cover. A cover the cook chose in review (a printed photo made the
/// cover, or a photo picked in the editor) is left alone: the choice runs only over the session's
/// candidates, when a candidate arrives.
@MainActor
enum CoverSelection {
    /// Vision's overall score for a photo, nil when it can't be scored or reads as a utility image.
    nonisolated static func score(_ data: Data) async -> Float? {
        guard let image = await ImageProcessing.thumbnail(from: data, maxPixelSize: 1_024)?.cgImage else { return nil }
        guard let observation = try? await CalculateImageAestheticsScoresRequest().perform(on: image) else { return nil }
        return observation.isUtility ? nil : observation.overallScore
    }

    /// Chooses among the recipe's cover candidates (its photos the session attached) and sets the
    /// cover to the best; the others keep their candidate caption. Nothing changes when the recipe
    /// has no candidates.
    static func choose(for recipe: Recipe, in context: ModelContext) async {
        let candidates = (recipe.images ?? []).filter { $0.role == .photo && ($0.caption == "Cover" || $0.caption == RecipeDraft.coverCandidateCaption) }
        guard candidates.count > 1 else { return }
        var best: (image: RecipeImage, score: Float)?
        for candidate in candidates {
            guard let data = candidate.imageData, let score = await score(data) else { continue }
            if best == nil || score > best!.score { best = (candidate, score) }
        }
        guard let chosen = best?.image, chosen.caption != "Cover" else { return }
        for candidate in candidates { candidate.caption = candidate == chosen ? "Cover" : RecipeDraft.coverCandidateCaption }
        if let data = chosen.imageData, let cover = await ImageProcessing.jpeg(from: data, maxPixelSize: 900, quality: 0.8) {
            recipe.coverImageData = cover
        }
        try? context.save()
    }
}
