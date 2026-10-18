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

/// "2 new recipes need a look ›" at the top of Recipes while any import waits for a check
/// (04 §5.1 Review prompt). Opens Needs a Look.
struct NeedsALookRow: View {
    let count: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text(count == 1 ? "1 new recipe needs a look" : "\(count) new recipes need a look")
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Imported with low confidence. Shows them to check against the page.")
    }
}

/// Needs a Look on iPhone: the recipes waiting for a check, newest first, each with what to check.
/// A recipe leaves the list once it is reviewed. iPad shows the same smart collection from its sidebar.
struct NeedsALookView: View {
    @Query(sort: [SortDescriptor(\Recipe.createdAt, order: .reverse)]) private var recipes: [Recipe]

    var body: some View {
        let pending = recipes.filter(\.needsReview)
        List(pending) { recipe in
            NavigationLink(value: LibraryRoute.recipe(recipe)) {
                VStack(alignment: .leading, spacing: 4) {
                    RecipeRow(recipe: recipe)
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                        Text(recipe.reviewTitle)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.leading, 68)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if pending.isEmpty {
                ContentUnavailableView {
                    Label("All checked", systemImage: "checkmark.circle")
                } description: {
                    Text("Every imported recipe has had its look.")
                }
            }
        }
        .navigationTitle("Needs a Look")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: pending.count)
    }
}
