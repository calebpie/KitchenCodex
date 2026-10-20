import Capture
import RecipeModel
import SwiftData
import SwiftUI
import Units

/// Read, scale, and start cooking (03 §3.3). Pushed on iPhone and over the grid in iPad's content
/// column, where a wide column lays ingredients beside steps. Delete pops the detail and deletes the
/// recipe once it is gone.
struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    /// Side by side: the space between the bars and the columns' frame, both in global
    /// coordinates, and the ingredients' height, which together keep the ingredients in view.
    @State private var barsFrame: CGRect = .zero
    @State private var columnsFrame: CGRect = .zero
    @State private var ingredientsHeight: CGFloat = 0

    private static let batchSteps: [Rational] = [Rational(1, 4), Rational(1, 2), Rational(3, 4), .one, Rational(3, 2), Rational(2), Rational(3), Rational(4)]
    /// The hero is lower in the wide layout, where the photo already spans the column (03 §3.3).
    private var heroHeight: CGFloat { isSideBySide ? 240 : 320 }

    private var version: RecipeVersion? { recipe.currentVersion }
    /// Pantry → Profile → Units; US until a profile exists.
    private var preferredSystem: MeasurementSystem { profiles.first?.unitPreference.measurementSystem ?? .us }
    /// Pantry → Profile → Temperature; °F until a profile exists.
    private var temperatureScale: TemperatureScale { profiles.first?.temperaturePreference.temperatureScale ?? .fahrenheit }
    /// Temperatures follow More → Units like amounts do, so a reading never mixes °F and °C:
    /// Preferred is the Profile's unit, US °F, Metric °C, and As Written converts none.
    private var shownTemperatureScale: TemperatureScale? {
        switch units {
        case .preferred: temperatureScale
        case .us: .fahrenheit
        case .metric: .celsius
        case .asWritten: nil
        }
    }
    private var hasHero: Bool { recipe.coverImageData != nil }
    /// iPad with room to spare: ingredients and steps side by side (03 §3.3).
    private var isSideBySide: Bool { sizeClass == .regular && contentWidth >= 820 }

    /// How far the ingredients column moves down so it stays under the bar while the steps beside
    /// it scroll, stopping where the steps end. Only when the whole column fits on screen; a longer
    /// one scrolls with the steps.
    private var ingredientsPin: CGFloat {
        guard ingredientsHeight > 0, ingredientsHeight <= barsFrame.height - 32 else { return 0 }
        return min(max(0, barsFrame.minY + 16 - columnsFrame.minY), max(0, columnsFrame.height - ingredientsHeight))
    }

    var body: some View {
        ZStack {
            // The space between the bars, which pinned ingredients stay inside. Measured here
            // because the page itself runs under the bar when there is a hero.
            Color.clear
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { barsFrame = $0 }
            page
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
                    if let version, hasMeasuredIngredients(version) || hasTemperatures(version) {
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
                        isDeleting = true
                        dismiss()
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

    /// The scrolling page: the hero, the header and the recipe.
    private var page: some View {
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
                            // The ingredients hug their longest line and the steps take the rest up
                            // to a readable measure; spare width goes to the trailing margin
                            // (04 §5.1 iPad columns).
                            HStack(alignment: .top, spacing: 40) {
                                ingredientsSection(for: version)
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { ingredientsHeight = $0 }
                                    .offset(y: ingredientsPin)
                                VStack(alignment: .leading, spacing: 28) {
                                    stepsSection(for: version)
                                    if !version.notes.isEmpty {
                                        notesSection(version.notes)
                                    }
                                }
                                .frame(maxWidth: Self.stepsMeasure + Self.stepNumberWidth, alignment: .leading)
                            }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { columnsFrame = $0 }
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

    /// Units also chooses °F or °C, so it shows for a recipe whose only measures are temperatures.
    private func hasTemperatures(_ version: RecipeVersion) -> Bool {
        let texts = version.sortedSteps.map(\.text) + [version.notes, recipe.headnote]
            + version.sortedIngredients.flatMap { [$0.item, $0.preparation ?? "", $0.note ?? ""] }
        return texts.contains(where: StepText.hasTemperatures)
    }

    // MARK: - Content

    /// The longest step line in the wide layout, about 660 pt, and the step number before it.
    static let stepsMeasure: CGFloat = 660
    static let stepNumberWidth: CGFloat = 36

    /// Beside the steps the ingredients are a column as wide as their longest line, at least 280 pt
    /// and at most a third of the two columns' width; stacked, the full width.
    private var ingredientsLayout: AnyLayout {
        guard isSideBySide else { return AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) }
        return AnyLayout(HuggingColumn(minWidth: 280, maxWidth: (min(contentWidth, 1_100) - 104) / 3, spacing: 12))
    }

    private func ingredientsSection(for version: RecipeVersion) -> some View {
        let factor = scaleFactor(for: version)
        return ingredientsLayout {
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
            // Scaling lengthens the header; it stacks rather than widen the column.
            .layoutValue(key: SetsColumnWidth.self, value: false)
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
                        IngredientLine(ingredient: ingredient, factor: factor, units: units, preferred: preferredSystem, temperatureScale: shownTemperatureScale)
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
                stepRow(step, number: index + 1)
            }
        }
    }

    /// One step: its number, then the text wrapping around the trailing thumbnail when the step has
    /// photos (04 §5.1 Step photos). At accessibility text sizes the wrap would leave a few words a
    /// line, so the thumbnail sits above the text instead.
    @ViewBuilder
    private func stepRow(_ step: Step, number: Int) -> some View {
        let photos = step.sortedPhotos
        let stacksPhoto = dynamicTypeSize.isAccessibilitySize
        HStack(alignment: stacksPhoto && !photos.isEmpty ? .top : .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.tint)
                .frame(minWidth: 24, alignment: .trailing)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                if stacksPhoto, !photos.isEmpty {
                    stepThumbnail(step, photos: photos, number: number)
                }
                StepTextView(text: step.text, scale: shownTemperatureScale, exclusion: stacksPhoto || photos.isEmpty ? nil : StepPhotoThumbnail.size)
                    // Temperatures read in the shown unit and times in full, with As Written as an action.
                    .pillTextAccessibility(step.text, scale: shownTemperatureScale, prefix: "Step \(number).")
                    .overlay(alignment: .topTrailing) {
                        if !stacksPhoto, !photos.isEmpty {
                            stepThumbnail(step, photos: photos, number: number)
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stepThumbnail(_ step: Step, photos: [RecipeImage], number: Int) -> some View {
        Button {
            viewedStepPhotos = StepPhotoSelection(step: step, stepNumber: number)
        } label: {
            StepPhotoThumbnail(photos: photos, stepNumber: number)
        }
        .buttonStyle(.plain)
    }

    /// The headnote and the notes use the step view, so their temperatures and times are pills too.
    private var headnoteSection: some View {
        DisclosureGroup {
            StepTextView(text: recipe.headnote, scale: shownTemperatureScale)
                .pillTextAccessibility(recipe.headnote, scale: shownTemperatureScale)
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
            StepTextView(text: notes, scale: shownTemperatureScale)
                .pillTextAccessibility(notes, scale: shownTemperatureScale)
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

/// The wide detail's ingredients column (04 §5.1 iPad columns): a leading stack, `spacing` apart,
/// as wide as its longest subview at its ideal width, held between `minWidth` and `maxWidth`, so a
/// short-lined recipe closes the gap to the steps and a long-lined one wraps at the cap. Subviews
/// whose `SetsColumnWidth` is false fit themselves into that width instead of setting it.
private struct HuggingColumn: Layout {
    var minWidth: CGFloat
    var maxWidth: CGFloat
    var spacing: CGFloat

    private func width(of subviews: Subviews) -> CGFloat {
        let longest = subviews.filter { $0[SetsColumnWidth.self] }.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return min(max(longest, minWidth), max(minWidth, maxWidth))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(of: subviews)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let proposal = ProposedViewSize(width: bounds.width, height: nil)
        var y = bounds.minY
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: proposal)
            y += subview.sizeThatFits(proposal).height + spacing
        }
    }
}

/// Whether a subview's ideal width counts toward `HuggingColumn`'s width.
nonisolated private struct SetsColumnWidth: LayoutValueKey {
    static let defaultValue = true
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
/// (04 §5.1 Ingredient lines). A temperature in the words ("oil, heated to 350°F") is a pill in the
/// shown unit, as in steps. Long-press shows the line as written.
private struct IngredientLine: View {
    let ingredient: Ingredient
    let factor: Rational
    let units: UnitChoice
    /// The Profile's units preference.
    let preferred: MeasurementSystem
    /// The unit temperatures are shown in; nil keeps them as written.
    let temperatureScale: TemperatureScale?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            if hasTemperatures {
                // The renderer draws the capsules; it takes the place of the numeric transition.
                line
                    .textRenderer(TemperaturePillRenderer())
            } else {
                line
                    .contentTransition(.numericText())
            }
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

    private var itemText: String { ingredient.item.isEmpty ? ingredient.rawText : ingredient.item }

    private var hasTemperatures: Bool {
        [itemText, ingredient.preparation ?? "", ingredient.note ?? ""].contains(where: StepText.hasTemperatures)
    }

    private var line: Text {
        let item = Text.withTemperaturePills(itemText, scale: temperatureScale, isSecondary: false)
        var text = item
        if let amount {
            text = Text("\(Text(amount).fontWeight(.semibold).monospacedDigit()) \(item)")
        }
        if let detail {
            text = Text("\(text)\(detail)")
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

    /// Everything after the item, in the secondary color: ", bone-in, thinly sliced", ", to taste",
    /// the note as its form says (" (about 3 oranges)", ", plus extra (for kneading)"), " (optional)",
    /// with temperatures as pills.
    private var detail: Text? {
        var text = ""
        if let preparation = ingredient.preparation, !preparation.isEmpty { text += ", \(preparation)" }
        if ingredient.cookingUnit == .toTaste { text += ", to taste" }
        if let note = ingredient.note, !note.isEmpty {
            text += NoteForm.suffix(for: note, form: ingredient.noteForm.flatMap(NoteForm.init(rawValue:)))
        }
        if ingredient.isOptional { text += " (optional)" }
        return text.isEmpty ? nil : Text.withTemperaturePills(text, scale: temperatureScale)
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
