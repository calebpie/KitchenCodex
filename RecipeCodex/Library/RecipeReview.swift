import RecipeModel
import SwiftData
import SwiftUI
import Units

// Review of low-confidence imports (02 Flow A step 5, 03 §3.3): which ingredients to check, and
// clearing the flag once the cook has looked.

extension Ingredient {
    /// A line that did not read as an amount and an item (03 §3.6): nothing parsed as the item, or
    /// no amount. "To taste" has no amount on purpose and is not flagged.
    var needsCheck: Bool {
        item.trimmed.isEmpty || quantity == nil
    }
}

extension Recipe {
    /// The current version's ingredients that did not read cleanly, in order.
    var ingredientsToCheck: [Ingredient] {
        (currentVersion?.sortedIngredients ?? []).filter(\.needsCheck)
    }

    /// "Check 3 ingredients", or "Check this recipe" when every line read cleanly but the import
    /// still had low confidence (its steps, say).
    var reviewTitle: String {
        let count = ingredientsToCheck.count
        if count == 0 { return "Check this recipe" }
        return count == 1 ? "Check 1 ingredient" : "Check \(count) ingredients"
    }

    /// The cook has looked: the current version no longer needs review.
    func markReviewed(in context: ModelContext) {
        currentVersion?.needsReview = false
        updatedAt = .now
        try? context.save()
    }
}

/// The yellow row at the top of a recipe that needs a look (03 §3.3): what to check, Review (the
/// editor at the ingredients), View Page, and Looks Right to clear it without changes.
struct ReviewBanner: View {
    let recipe: Recipe
    var onReview: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onReview) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.reviewTitle)
                            .font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the editor at the ingredients.")

            HStack(spacing: 12) {
                Button("Review", action: onReview)
                    .buttonStyle(.borderedProminent)
                if let url = recipe.source?.url {
                    Link(destination: url) {
                        Label("View Page", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
                Button("Looks Right") {
                    withAnimation { recipe.markReviewed(in: modelContext) }
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(14)
        .background(.yellow.opacity(0.16), in: .rect(cornerRadius: 16))
    }

    private var detail: String {
        var parts: [String] = []
        if let site = recipe.source?.siteName ?? recipe.source?.url?.host() {
            parts.append("Imported from \(site) with low confidence.")
        } else {
            parts.append("Imported with low confidence.")
        }
        let count = recipe.ingredientsToCheck.count
        parts.append(count == 0 ? "Compare it with the page." : (count == 1 ? "One line has no amount or item." : "\(count) lines have no amount or item."))
        return parts.joined(separator: " ")
    }
}

/// Provenance for review (03 §1 principle 4): how each stored line was read, under it the line as
/// the page wrote it, and a mark on the lines to check.
struct IngredientProvenanceRows: View {
    let ingredients: [Ingredient]

    var body: some View {
        ForEach(ingredients) { ingredient in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: ingredient.needsCheck ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(ingredient.needsCheck ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
                    .accessibilityLabel(ingredient.needsCheck ? "Check this line" : "Read cleanly")
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(amount(of: ingredient))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text(ingredient.item.isEmpty ? "No item" : ingredient.item)
                            .foregroundStyle(ingredient.item.isEmpty ? .secondary : .primary)
                    }
                    Text("“\(ingredient.rawText)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("From the page: \(ingredient.rawText)")
                }
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
            .id(ingredient.persistentModelID)
        }
    }

    private func amount(of ingredient: Ingredient) -> String {
        guard let quantity = ingredient.quantity else { return "No amount" }
        if quantity.unit == .toTaste { return "To taste" }
        return quantity.formatted()
    }
}
