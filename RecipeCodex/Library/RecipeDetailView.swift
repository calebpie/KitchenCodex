import Capture
import RecipeModel
import SwiftData
import SwiftUI
import Units

/// Read, scale, and start cooking (03 §3.3).
struct RecipeDetailView: View {
    let recipe: Recipe
    /// Set by the iPad split view, which deletes the recipe and clears its selection. Without it the
    /// detail pops itself and deletes the recipe once it is gone.
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext

    /// Servings chosen in the scale popover, or `nil` for the recipe as written. Transient: the
    /// stored recipe changes only in the editor (04 §5.1 Detail scale).
    @State private var servings: Int?
    /// Multiplier for recipes that give no servings.
    @State private var batchIndex = RecipeDetailView.batchSteps.firstIndex(of: .one)!
    @State private var isScaling = false
    /// More → Units; transient like the scale (04 §5.1 Detail units).
    @State private var units: UnitChoice = .preferred
    @Query(sort: [SortDescriptor(\UserProfile.createdAt)]) private var profiles: [UserProfile]
    @State private var isEditing = false
    @State private var isReviewing = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var showsNavigationTitle = false
    @State private var viewedStepPhotos: StepPhotoSelection?
    @State private var isNamingCollection = false
    @State private var contentWidth: CGFloat = 0

    private static let batchSteps: [Rational] = [Rational(1, 4), Rational(1, 2), Rational(3, 4), .one, Rational(3, 2), Rational(2), Rational(3), Rational(4)]
    private let heroHeight: CGFloat = 320

    private var version: RecipeVersion? { recipe.currentVersion }
    /// Pantry → Profile → Units; US until a profile exists.
    private var preferredSystem: MeasurementSystem { profiles.first?.unitPreference.measurementSystem ?? .us }
    /// Pantry → Profile → Temperature; °F until a profile exists.
    private var temperatureScale: TemperatureScale { profiles.first?.temperaturePreference.temperatureScale ?? .fahrenheit }
    private var hasHero: Bool { recipe.coverImageData != nil }
    /// iPad with room to spare: ingredients and steps side by side (03 §3.3).
    private var isSideBySide: Bool { sizeClass == .regular && contentWidth >= 820 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hasHero {
                    // The photo fills a screen-wide frame as an overlay, so a wide or tall photo
                    // never widens the page.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: heroHeight)
                        .overlay { RecipeCoverImage(recipe: recipe, pointSize: 440, usesFullPhoto: true) }
                        .clipped()
                        // iPad: the hero carries on under the sidebar (03 §3.3).
                        .backgroundExtensionEffect(isEnabled: sizeClass == .regular)
                }

                VStack(alignment: .leading, spacing: 28) {
                    if recipe.needsReview {
                        ReviewBanner(recipe: recipe) { isReviewing = true }
                            .transition(.opacity)
                    }
                    header
                    if !recipe.headnote.isEmpty {
                        headnoteSection
                    }
                    if let version {
                        if isSideBySide {
                            HStack(alignment: .top, spacing: 40) {
                                ingredientsSection(for: version)
                                .frame(width: (min(contentWidth, 1_100) - 104) * 0.4, alignment: .leading)
                                VStack(alignment: .leading, spacing: 28) {
                                    stepsSection(for: version)
                                    if !version.notes.isEmpty {
                                        notesSection(version.notes)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            ingredientsSection(for: version)
                            stepsSection(for: version)
                            if !version.notes.isEmpty {
                                notesSection(version.notes)
                            }
                        }
                    }
                    versionsSection
                }
                .padding(.horizontal, isSideBySide ? 32 : 16)
                .padding(.top, hasHero ? 20 : 8)
                .padding(.bottom, 32)
                .frame(maxWidth: isSideBySide ? 1_100 : 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        // The hero runs under the navigation bar; once content scrolls beneath the bar the hard edge
        // gives the title bar a defined edge over step text (04 §5.1 Floating headers).
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .ignoresSafeArea(edges: hasHero ? .top : [])
        .scrollEdgeEffectStyle(.hard, for: .top)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > (hasHero ? heroHeight : 40)
        } action: { _, isPastTitle in
            showsNavigationTitle = isPastTitle
        }
        .navigationTitle(showsNavigationTitle ? recipe.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The pencil, not the word (04 §5.1 Edit glyph).
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { isEditing = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Share lives here, not in its own bubble (04 §5.1 Detail share).
                    ShareRecipeMenu(recipe: recipe) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: recipe.isFavorite ? "heart.slash" : "heart") {
                        recipe.isFavorite.toggle()
                    }
                    AddToCollectionMenu(recipe: recipe) { isNamingCollection = true }
                    if let version, hasMeasuredIngredients(version) {
                        Divider()
                        Picker(selection: $units) {
                            ForEach(UnitChoice.allCases) { choice in
                                Text(choice.title(preferred: preferredSystem)).tag(choice)
                            }
                        } label: {
                            Label("Units", systemImage: "ruler")
                        }
                        .pickerStyle(.menu)
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
                        if let onDelete {
                            onDelete()
                        } else {
                            isDeleting = true
                            dismiss()
                        }
                    }
                } message: {
                    Text("The recipe and all its versions will be deleted.")
                }
            }
            // Bottom toolbar: the prominent Cook alone (04 §5.1 Detail share); Add to menu arrives with Plan.
            ToolbarItem(placement: .bottomBar) {
                Button {
                    // Cook mode arrives in Phase 3.
                } label: {
                    // An explicit row: a bottom toolbar shows a Label as its icon only.
                    HStack(spacing: 6) {
                        Image(systemName: "frying.pan")
                        Text("Cook")
                    }
                    .padding(.horizontal, 24)
                }
                .buttonStyle(.glassProminent)
                .disabled(true)
                .accessibilityHint("Cook mode is coming in a later version.")
            }
        }
        // iPhone: the bottom toolbar (Cook) only shows without the tab bar; detail is a focused,
        // pushed screen. iPad keeps its tab bar at the top.
        .toolbarVisibility(sizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .sheet(isPresented: $isEditing) {
            RecipeEditorView(recipe: recipe)
        }
        .sheet(isPresented: $isReviewing) {
            RecipeEditorView(recipe: recipe, isReviewing: true)
        }
        .fullScreenCover(item: $viewedStepPhotos) { selection in
            StepPhotoViewer(selection: selection)
        }
        .collectionNamePrompt("New Collection", isPresented: $isNamingCollection, actionTitle: "Create") { name in
            CollectionActions.create(named: name, adding: recipe, in: modelContext)
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

            if let url = recipe.source?.url {
                // Provenance is one tap from the source (03 §1 principle 4).
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(sourceLine)
                        Image(systemName: "arrow.up.right")
                            .imageScale(.small)
                    }
                }
                .font(.subheadline)
                .accessibilityHint("Opens the recipe's web page.")
            } else {
                Text(sourceLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            metadata
        }
    }

    private var sourceLine: String { recipe.sourceLine }

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

    private func isScaled(_ version: RecipeVersion) -> Bool {
        scaleFactor(for: version) != .one
    }

    /// "4 servings", "6 servings · scaled from 4", "× 1", "× 1½".
    private func scaleTitle(for version: RecipeVersion) -> String {
        if let base = version.servings {
            let shown = servings ?? base
            let title = shown == 1 ? "1 serving" : "\(shown) servings"
            return shown == base ? title : "\(title) · scaled from \(base)"
        }
        return "× \(Self.batchSteps[batchIndex].mixedNumberString)"
    }

    /// The scale in the Ingredients header (04 §5.1 Detail scale): tap for the popover.
    private func scaleButton(for version: RecipeVersion) -> some View {
        Button {
            isScaling = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(scaleTitle(for: version))
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .fontWeight(.semibold)
            }
            .font(.headline)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Scale")
        .accessibilityValue(scaleTitle(for: version))
        .accessibilityHint("Changes the amounts for this reading. The recipe stays as written.")
        .popover(isPresented: $isScaling) {
            scalePopover(for: version)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func scalePopover(for version: RecipeVersion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let base = version.servings {
                Stepper(value: Binding { servings ?? base } set: { servings = $0 == base ? nil : $0 }, in: 1...200) {
                    Text((servings ?? base) == 1 ? "1 serving" : "\(servings ?? base) servings")
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .accessibilityValue("\(servings ?? base) servings")
            } else {
                Stepper(value: $batchIndex, in: 0...(Self.batchSteps.count - 1)) {
                    Text("Batch × \(Self.batchSteps[batchIndex].mixedNumberString)")
                        .font(.headline)
                        .monospacedDigit()
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(scaleFootnote(for: version))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Reset") {
                    servings = nil
                    batchIndex = Self.batchSteps.firstIndex(of: .one)!
                }
                .disabled(!isScaled(version))
            }
        }
        .padding(20)
        .frame(minWidth: 280, idealWidth: 320)
        .animation(.default, value: servings)
        .animation(.default, value: batchIndex)
    }

    private func scaleFootnote(for version: RecipeVersion) -> String {
        if let base = version.servings {
            return isScaled(version) ? "Scaled from \(base). The recipe stays as written." : "As written."
        }
        return isScaled(version) ? "The recipe stays as written." : "As written."
    }

    private func hasMeasuredIngredients(_ version: RecipeVersion) -> Bool {
        // Spoons count: they become millilitres in metric once they add up past half a cup.
        version.sortedIngredients.contains { $0.cookingUnit?.isConvertible == true }
    }

    // MARK: - Content

    private func ingredientsSection(for version: RecipeVersion) -> some View {
        let factor = scaleFactor(for: version)
        return VStack(alignment: .leading, spacing: 12) {
            // "Ingredients · 4 servings ⌄"; stacked when the two don't fit on a line.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SectionTitle("Ingredients")
                    Text("·")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    scaleButton(for: version)
                }
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle("Ingredients")
                    scaleButton(for: version)
                }
            }
            if version.sortedIngredients.isEmpty {
                Text("No ingredients yet.").foregroundStyle(.secondary)
            }
            ForEach(Self.ingredientGroups(version.sortedIngredients), id: \.offset) { group in
                VStack(alignment: .leading, spacing: 12) {
                    if let name = group.name {
                        Text(name)
                            .font(.headline)
                            .padding(.top, group.offset == 0 ? 0 : 8)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(group.ingredients) { ingredient in
                        IngredientLine(ingredient: ingredient, factor: factor, units: units, preferred: preferredSystem)
                    }
                }
            }
        }
    }

    /// Runs of ingredients that share a group heading, in order (03 §3.3: grouped by component).
    static func ingredientGroups(_ ingredients: [Ingredient]) -> [(offset: Int, name: String?, ingredients: [Ingredient])] {
        var groups: [(offset: Int, name: String?, ingredients: [Ingredient])] = []
        for ingredient in ingredients {
            let name = ingredient.group.flatMap { $0.isEmpty ? nil : $0 }
            if let last = groups.last, last.name == name {
                groups[groups.count - 1].ingredients.append(ingredient)
            } else {
                groups.append((groups.count, name, [ingredient]))
            }
        }
        return groups
    }

    private func stepsSection(for version: RecipeVersion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Steps")
            if version.sortedSteps.isEmpty {
                Text("No steps yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(version.sortedSteps.enumerated()), id: \.element.id) { index, step in
                let conversions = StepText.conversions(in: step.text, scale: temperatureScale)
                HStack(alignment: .top, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                            .frame(minWidth: 24, alignment: .trailing)
                        // Temperatures as pills in the preferred unit (04 §5.1); long-press for the original.
                        StepText(text: step.text, scale: temperatureScale)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(StepTemperatureLongPress(conversions: conversions))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(index + 1). \(StepText.spoken(step.text, in: temperatureScale))")

                    let photos = step.sortedPhotos
                    if !photos.isEmpty {
                        Button {
                            viewedStepPhotos = StepPhotoSelection(step: step, stepNumber: index + 1)
                        } label: {
                            StepPhotoThumbnail(photos: photos, stepNumber: index + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var headnoteSection: some View {
        DisclosureGroup {
            Text(recipe.headnote)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Headnote")
                .font(.headline)
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

/// More → Units on recipe detail (04 §5.1 Detail units): the Profile's preference, a system, or
/// the units the recipe wrote.
enum UnitChoice: String, CaseIterable, Identifiable {
    case preferred, us, metric, asWritten

    var id: Self { self }

    func title(preferred system: MeasurementSystem) -> String {
        switch self {
        case .preferred: "Preferred (\(system == .us ? "US" : "Metric"))"
        case .us: "US"
        case .metric: "Metric"
        case .asWritten: "As Written"
        }
    }
}

/// One ingredient, scaled and converted: the amount bold, the item in the primary color, and the
/// preparation, note and "(optional)" in the secondary color at the same size and weight
/// (04 §5.1 Ingredient lines). Long-press shows the line as written.
private struct IngredientLine: View {
    let ingredient: Ingredient
    let factor: Rational
    let units: UnitChoice
    /// The Profile's units preference.
    let preferred: MeasurementSystem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            line
                .contentTransition(.numericText())
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.default, value: amount)
        .contentShape(.rect)
        .contextMenu {
            Section("As Written") {
                Label(ingredient.rawText, systemImage: "text.quote")
            }
        }
    }

    private var line: Text {
        let item = Text(ingredient.item.isEmpty ? ingredient.rawText : ingredient.item)
        var text = item
        if let amount {
            text = Text("\(Text(amount).fontWeight(.semibold).monospacedDigit()) \(item)")
        }
        if let detail {
            text = Text("\(text)\(Text(detail).foregroundStyle(.secondary))")
        }
        return text
    }

    /// Scaled exactly, then re-expressed in a system, then rounded to what a cook can measure.
    /// Under Preferred, an amount written in the other system is converted to the preferred one
    /// (04 §5.1 Units preference); one already in it, any spoon, count, and metric weight under
    /// the US preference stays as written, changing unit only when scaling makes the written unit
    /// awkward (¼ cup × 1.5 is 6 tbsp). US or Metric converts everything; As Written converts nothing.
    private var amount: String? {
        guard let quantity = ingredient.quantity, quantity.unit != .toTaste else { return nil }
        var shown = quantity.scaled(by: factor)
        if let target = Self.targetSystem(for: quantity.unit, units: units, preferred: preferred, isScaled: factor != .one) {
            shown = shown.displayed(in: target)
        }
        return shown.friendlyRounded().formatted()
    }

    /// The system to display an amount in, or nil to leave it as written. Grams and kilograms stay
    /// metric under the US preference so precise recipes keep their weights; millilitres and litres
    /// still become cups. US or Metric converts everything; As Written keeps each amount's own
    /// system, re-picking the unit only when scaled.
    static func targetSystem(for unit: CookingUnit?, units: UnitChoice, preferred: MeasurementSystem, isScaled: Bool) -> MeasurementSystem? {
        switch units {
        case .us: return .us
        case .metric: return .metric
        case .asWritten: return isScaled ? unit?.system : nil
        case .preferred: break
        }
        guard let unit, let own = unit.system else { return nil }
        let keepsMetricWeight = preferred == .us && own == .metric && unit.isMass
        if own != preferred, unit.isConvertible, !unit.isSpoon, !keepsMetricWeight { return preferred }
        return isScaled ? own : nil
    }

    /// Everything after the item: ", bone-in, thinly sliced", ", to taste", " (about 3 oranges)",
    /// " (optional)".
    private var detail: String? {
        var text = ""
        if let preparation = ingredient.preparation, !preparation.isEmpty { text += ", \(preparation)" }
        if ingredient.cookingUnit == .toTaste { text += ", to taste" }
        if let note = ingredient.note, !note.isEmpty { text += " (\(note))" }
        if ingredient.isOptional { text += " (optional)" }
        return text.isEmpty ? nil : text
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
