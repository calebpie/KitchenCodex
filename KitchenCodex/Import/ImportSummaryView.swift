import Capture
import SwiftUI

/// The top of the import preview (03 §3.4), shared by the Share Extension and the in-app sheet:
/// cover, title, source, detected yield and time, ingredient and step counts, and the status line.
struct ImportSummaryView: View {
    let recipe: ImportedRecipe
    var cover: UIImage?
    /// The title is shown here in the Share Extension; the in-app sheet edits it in a field instead.
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityLabel("Cover photo")
            }
            if showsTitle {
                Text(recipe.title.isEmpty ? "Untitled Recipe" : recipe.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(sourceLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if recipe.method != nil {
                Label(counts, systemImage: "list.bullet")
                    .font(.subheadline)
            }
            Label(recipe.statusLine, systemImage: statusSymbol)
                .font(.footnote)
                .foregroundStyle(recipe.needsReview || recipe.method == nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceLine: String {
        [recipe.sourceName, recipe.author].compactMap(\.self).joined(separator: " · ")
    }

    private var details: [String] {
        var parts: [String] = []
        if let servings = recipe.servings, recipe.yieldDescription == nil {
            parts.append("Serves \(servings)")
        } else if let yield = recipe.yieldDescription {
            parts.append(yield)
        }
        if let time = recipe.totalTime ?? recipe.cookTime {
            parts.append(time.formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2)))
        }
        return parts
    }

    private var counts: String {
        let ingredients = recipe.ingredients.count == 1 ? "1 ingredient" : "\(recipe.ingredients.count) ingredients"
        let steps = recipe.steps.count == 1 ? "1 step" : "\(recipe.steps.count) steps"
        return "\(ingredients), \(steps)"
    }

    private var statusSymbol: String {
        switch recipe.method {
        case .jsonLD?, .microdata?, .libraryFile?: "checkmark.circle"
        case .model?: "apple.intelligence"
        case .pageText?: "exclamationmark.triangle"
        case nil: "square.and.pencil"
        }
    }
}

/// The top of the preview for an article saved as reference reading (02 §4.2): title, source, the
/// sections it has, and what saving does. Shared by the Share Extension and the in-app sheet.
struct ReferenceSummaryView: View {
    let reference: ImportedReference
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                Text(reference.title.isEmpty ? "Untitled Article" : reference.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text([reference.sourceName, reference.author].compactMap(\.self).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(sectionsLine, systemImage: "text.book.closed")
                .font(.subheadline)
            if !reference.headings.isEmpty {
                Text(reference.headings.prefix(4).joined(separator: " · ") + (reference.headings.count > 4 ? " · …" : ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Label("An article, not a recipe. It saves as reference reading in Pantry → References, beside the recipes it informs.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionsLine: String {
        let count = reference.sections.count
        let words = reference.characterCount / 5
        return "\(count == 1 ? "1 section" : "\(count) sections"), about \(words.formatted()) words"
    }
}
