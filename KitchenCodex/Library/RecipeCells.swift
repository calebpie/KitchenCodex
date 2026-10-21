import RecipeModel
import SwiftUI

/// A grid card: image-led, with title, time and a "Never cooked" or book badge (03 §3.2).
struct RecipeCard: View {
    let recipe: Recipe

    private let cornerRadius: CGFloat = 22
    private let inset: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { RecipeCoverImage(recipe: recipe, pointSize: 220) }
                // Concentric with the card: the image's radius is the card's minus the inset.
                .clipShape(ConcentricRectangle(corners: .concentric(minimum: 8), isUniform: true))
                .overlay(alignment: .topTrailing) {
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.footnote)
                            .padding(6)
                            .background(.regularMaterial, in: .circle)
                            .padding(6)
                            .accessibilityLabel("Favorite")
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                RecipeMetadataLine(recipe: recipe)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .padding(inset)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.secondary, in: .rect(cornerRadius: cornerRadius))
        .containerShape(.rect(cornerRadius: cornerRadius))
        .contentShape(.rect(cornerRadius: cornerRadius))
        .accessibilityElement(children: .combine)
    }
}

/// A list row: text-led, with a small cover.
struct RecipeRow: View {
    let recipe: Recipe
    /// The ingredient a search matched, shown under the title.
    var matchedIngredient: String?

    var body: some View {
        HStack(spacing: 12) {
            RecipeCoverImage(recipe: recipe, pointSize: 64)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(recipe.title)
                        .font(.headline)
                        .lineLimit(2)
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Favorite")
                    }
                }
                if let matchedIngredient {
                    Text("Uses \(matchedIngredient)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                RecipeMetadataLine(recipe: recipe, showsCourse: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Course, time and cooked state on one line.
struct RecipeMetadataLine: View {
    let recipe: Recipe
    var showsCourse = false

    var body: some View {
        HStack(spacing: 6) {
            if showsCourse, let course = recipe.course {
                Text(course)
            }
            if let time = recipe.currentVersion?.displayTime {
                Label(time, systemImage: "clock")
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
            }
            if recipe.book != nil {
                Image(systemName: "books.vertical")
                    .accessibilityLabel("From a cookbook")
            }
            if recipe.isNeverCooked {
                NeverCookedBadge()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct NeverCookedBadge: View {
    var body: some View {
        Text("Never cooked")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.fill.tertiary, in: .capsule)
    }
}
