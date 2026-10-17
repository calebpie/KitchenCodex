import RecipeModel
import SwiftData
import SwiftUI
import Units

/// Read, scale, and start cooking (03 §3.3).
struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Servings chosen with the stepper, or `nil` for the recipe as written.
    @State private var servings: Int?
    /// Multiplier for recipes that give no servings.
    @State private var batchIndex = RecipeDetailView.batchSteps.firstIndex(of: .one)!
    /// `nil` shows each ingredient as written; once the cook picks a system everything converts to it.
    @State private var unitSystem: MeasurementSystem?
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var showsNavigationTitle = false

    private static let batchSteps: [Rational] = [Rational(1, 4), Rational(1, 2), Rational(3, 4), .one, Rational(3, 2), Rational(2), Rational(3), Rational(4)]
    private let heroHeight: CGFloat = 320

    private var version: RecipeVersion? { recipe.currentVersion }
    private var hasHero: Bool { recipe.coverImageData != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hasHero {
                    RecipeCoverImage(recipe: recipe, pointSize: 440, usesFullPhoto: true)
                        .frame(height: heroHeight)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 28) {
                    header
                    if let version {
                        scalingControls(for: version)
                        ingredientsSection(for: version)
                        stepsSection(for: version)
                        if !version.notes.isEmpty {
                            notesSection(version.notes)
                        }
                    }
                    versionsSection
                }
                .padding(.horizontal)
                .padding(.top, hasHero ? 20 : 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        // The hero runs under the navigation bar; the soft edge effect keeps Back and the toolbar legible over it.
        .ignoresSafeArea(edges: hasHero ? .top : [])
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > (hasHero ? heroHeight : 40)
        } action: { _, isPastTitle in
            showsNavigationTitle = isPastTitle
        }
        .navigationTitle(showsNavigationTitle ? recipe.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: recipe.isFavorite ? "heart.slash" : "heart") {
                        recipe.isFavorite.toggle()
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .confirmationDialog("Delete “\(recipe.title)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete Recipe", role: .destructive) {
                        isDeleting = true
                        dismiss()
                    }
                } message: {
                    Text("The recipe and all its versions will be deleted.")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    // Cook mode arrives in Phase 3.
                } label: {
                    Label("Cook", systemImage: "frying.pan")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.glassProminent)
                .disabled(true)
                .accessibilityHint("Cook mode is coming in a later version.")
            }
        }
        // The bottom toolbar (Cook) only shows without the tab bar; detail is a focused, pushed screen.
        .toolbarVisibility(.hidden, for: .tabBar)
        .sheet(isPresented: $isEditing) {
            RecipeEditorView(recipe: recipe)
        }
        .onChange(of: version?.servings) {
            // A new version may have a different yield; start again from it.
            servings = nil
        }
        .onDisappear {
            // Delete after the pop so the view never renders a deleted model.
            guard isDeleting else { return }
            modelContext.delete(recipe)
            try? modelContext.save()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recipe.title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(sourceLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            metadata
        }
    }

    private var sourceLine: String {
        if let book = recipe.book {
            let page = recipe.pageNumber.map { ", p. \($0)" } ?? ""
            return "\(book.title)\(page)"
        }
        if let source = recipe.source {
            let site = source.siteName ?? source.url?.host() ?? ""
            return [site, source.author].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        }
        return "Added by hand · \(recipe.createdAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { metadataItems }
            VStack(alignment: .leading, spacing: 6) { metadataItems }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var metadataItems: some View {
        if let version {
            if let time = version.displayTime {
                Label(time, systemImage: "clock")
            }
            if !version.yieldText.isEmpty {
                Label(version.yieldText, systemImage: "fork.knife")
            }
        }
        if let course = recipe.course {
            Label(course, systemImage: "menucard")
        }
        if recipe.isNeverCooked {
            NeverCookedBadge()
        } else {
            Label("Cooked \(recipe.cookCount)×", systemImage: "checkmark.circle")
        }
    }

    // MARK: - Scaling

    private func scaleFactor(for version: RecipeVersion) -> Rational {
        if let base = version.servings, let servings { return Rational(servings, base) }
        if version.servings == nil { return Self.batchSteps[batchIndex] }
        return .one
    }

    @ViewBuilder
    private func scalingControls(for version: RecipeVersion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let base = version.servings {
                Stepper(value: Binding { servings ?? base } set: { servings = $0 }, in: 1...200) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Serves \(servings ?? base)")
                            .font(.headline)
                            .contentTransition(.numericText())
                        if let servings, servings != base {
                            Text("Scaled from \(base)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityValue("\(servings ?? base) servings")
            } else {
                Stepper(value: $batchIndex, in: 0...(Self.batchSteps.count - 1)) {
                    Text("Batch × \(Self.batchSteps[batchIndex].description)")
                        .font(.headline)
                }
            }

            if hasMeasuredIngredients(version) {
                Picker("Units", selection: Binding { unitSystem ?? dominantSystem(version) } set: { unitSystem = $0 }) {
                    Text("US").tag(MeasurementSystem.us)
                    Text("Metric").tag(MeasurementSystem.metric)
                }
                .pickerStyle(.segmented)
            }
        }
        .animation(.default, value: servings)
    }

    private func dominantSystem(_ version: RecipeVersion) -> MeasurementSystem {
        MeasurementSystem.dominant(in: version.sortedIngredients.map(\.cookingUnit)) ?? .us
    }

    private func hasMeasuredIngredients(_ version: RecipeVersion) -> Bool {
        // Spoons count: they become milliliters in metric once they add up.
        version.sortedIngredients.contains { $0.cookingUnit?.system != nil || $0.cookingUnit == .teaspoon || $0.cookingUnit == .tablespoon }
    }

    // MARK: - Content

    private func ingredientsSection(for version: RecipeVersion) -> some View {
        let factor = scaleFactor(for: version)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Ingredients")
            if version.sortedIngredients.isEmpty {
                Text("No ingredients yet.").foregroundStyle(.secondary)
            }
            ForEach(version.sortedIngredients) { ingredient in
                IngredientLine(ingredient: ingredient, factor: factor, system: unitSystem)
            }
        }
    }

    private func stepsSection(for version: RecipeVersion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Steps")
            if version.sortedSteps.isEmpty {
                Text("No steps yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(version.sortedSteps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .frame(minWidth: 24, alignment: .trailing)
                    Text(step.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(step.text)")
            }
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Notes")
            Text(notes)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var versionsSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(recipe.sortedVersions.reversed()) { version in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Version \(version.versionNumber)")
                                .font(.subheadline.weight(.semibold))
                            if version.id == recipe.currentVersion?.id {
                                Text("Current")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.tint.quaternary, in: .capsule)
                            }
                            Spacer()
                            Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !version.changeSummary.isEmpty {
                            Text(version.changeSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Versions (\(recipe.versions?.count ?? 0))")
                .font(.headline)
        }
    }
}

private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
    }
}

/// One ingredient, scaled and converted, with the amount in bold.
private struct IngredientLine: View {
    let ingredient: Ingredient
    let factor: Rational
    let system: MeasurementSystem?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            if let amount {
                Text("\(Text(amount).fontWeight(.semibold).monospacedDigit()) \(description)")
                    .contentTransition(.numericText())
            } else {
                Text(description)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.default, value: amount)
    }

    private var amount: String? {
        guard let quantity = ingredient.quantity, quantity.unit != .toTaste else { return nil }
        return quantity.friendly(scaledBy: factor, in: system).formatted()
    }

    private var description: String {
        var text = ingredient.item
        if let preparation = ingredient.preparation, !preparation.isEmpty { text += ", \(preparation)" }
        if ingredient.cookingUnit == .toTaste { text += ", to taste" }
        if ingredient.isOptional { text += " (optional)" }
        return text
    }
}

extension Ingredient {
    var cookingUnit: CookingUnit? { unit.flatMap(CookingUnit.init(rawValue:)) }

    /// The stored rational amount; `nil` when the line has none. "To taste" has a unit and no amount.
    var quantity: Quantity? {
        if cookingUnit == .toTaste { return Quantity(.zero, .toTaste) }
        guard let numerator = quantityNumerator else { return nil }
        return Quantity(Rational(numerator, max(1, quantityDenominator ?? 1)), cookingUnit)
    }
}
