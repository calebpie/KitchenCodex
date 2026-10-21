import Capture
import RecipeModel
import SwiftUI

/// Scan review (03 §3.6): the structured recipe and the page it came from. On iPhone two stacked
/// panes with a draggable divider, the recipe above and the page below; on iPad side by side, the
/// page on the left. Tap a region and assign it from the floating control (a popover on iPad, where
/// a lasso picks several and hovering previews a region's text); tap an item and its source region
/// flashes, tap it again to correct its wording. Undo steps back through every change. The sheet
/// around it holds Cancel and Save.
struct ScanReviewView: View {
    @Bindable var model: ScanReviewModel
    /// The book the page is from, for the line that says why review was asked and for its
    /// cross-reference cards.
    var book: Book?
    /// A stored recipe under review again, which its pointers don't link to itself.
    var stored: Recipe?
    var bookTitle: String? { book?.displayTitle }
    /// More → Rescan: read the photo again. Nil hides it.
    var onRescan: (() -> Void)?
    /// A page scanned on its own offers Skip for each recipe on it (ux-notes row 60).
    var offersSkip = true

    @AppStorage("scan.explainedFirstReview") private var hasExplainedFirstReview = false
    /// The width the review has: side by side from 700 pt (an iPad sheet), stacked under it.
    @State private var width: CGFloat = 0
    @State private var showsExplanation = false
    @State private var images: [Int: UIImage] = [:]
    @State private var shownPage = 0
    /// iPhone: the recipe pane's share of the height, set by the divider.
    @State private var topShare: CGFloat = 0.5
    @GestureState private var dividerDrag: CGFloat = 0
    @State private var focusRect: CGRect?
    @State private var lastTapped: ReviewItem.ID?
    @State private var editingText = ""
    @FocusState private var editingFocus: ReviewItem.ID?
    @State private var popoverRegion: Int?
    @State private var isConfirmingRescan = false
    @State private var isSplitting = false

    private var isWide: Bool { width >= 700 }
    private static let dividerHeight: CGFloat = 22

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 0) {
                    pagePane
                        .frame(maxWidth: .infinity)
                    Divider()
                    structurePane
                        .frame(width: min(440, width * 0.42))
                }
            } else {
                GeometryReader { geometry in
                    let share = min(0.8, max(0.2, topShare + dividerDrag / max(1, geometry.size.height)))
                    VStack(spacing: 0) {
                        // The divider is a bar the recipe scrolls under, with the system's scroll
                        // edge, so the pane reads as scrollable where it cuts off (ux-notes row 71).
                        structurePane
                            .safeAreaBar(edge: .bottom, spacing: 0) { divider(height: geometry.size.height) }
                            .scrollEdgeEffectStyle(.soft, for: .bottom)
                            .frame(height: geometry.size.height * share + Self.dividerHeight)
                        pagePane
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .toolbar { reviewToolbar }
        .task(id: model.pages.map(\.id)) { await loadImages() }
        .onAppear {
            showsExplanation = !hasExplainedFirstReview && model.recipes.contains { !$0.reasons.filter(ScanGate.forcing.contains).isEmpty }
            if showsExplanation { hasExplainedFirstReview = true }
        }
        .onChange(of: editingFocus) { old, new in
            if let old, new != old { commitEdit(old) }
        }
        .confirmationDialog("Read the photo again?", isPresented: $isConfirmingRescan, titleVisibility: .visible) {
            Button("Rescan", role: .destructive) { onRescan?() }
        } message: {
            Text("Your changes to this page are dropped.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var reviewToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                withAnimation { model.undo() }
            }
            .disabled(!model.hasChanges)
            .keyboardShortcut("z")
        }
        if (offersSkip && model.recipes.count > 1) || onRescan != nil {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if offersSkip, model.recipes.count > 1 {
                    Button(model.recipe.isSkipped ? "Include This Recipe" : "Skip This Recipe",
                           systemImage: model.recipe.isSkipped ? "plus.circle" : "minus.circle") {
                        withAnimation { model.toggleSkip() }
                    }
                }
                if onRescan != nil {
                    Button("Rescan", systemImage: "arrow.clockwise") {
                        if model.hasChanges { isConfirmingRescan = true } else { onRescan?() }
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
        }
    }

    // MARK: - The divider

    private func divider(height: CGFloat) -> some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: Self.dividerHeight)
            .contentShape(.rect)
            .gesture(
                DragGesture()
                    .updating($dividerDrag) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        topShare = min(0.8, max(0.2, topShare + value.translation.height / max(1, height)))
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Divider")
            .accessibilityValue("\(Int(topShare * 100)) percent recipe")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: topShare = min(0.8, topShare + 0.1)
                case .decrement: topShare = max(0.2, topShare - 0.1)
                @unknown default: break
                }
            }
    }

    // MARK: - The page

    private var pagePane: some View {
        VStack(spacing: 0) {
            if model.pages.count > 1 {
                Picker("Page", selection: $shownPage) {
                    ForEach(model.pages) { page in
                        Text(page.pageNumber.map { "p. \($0)" } ?? "Photo \(page.id + 1)").tag(page.id)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            ZoomablePage(aspectRatio: aspectRatio, focus: focusRect) {
                PageRegionsView(
                    image: images[shownPage],
                    regions: model.regions.filter { $0.page == shownPage },
                    role: model.shownRole(of:),
                    label: regionLabel,
                    isDimmed: { !model.isInCurrentRecipe($0) },
                    selected: Set([model.selectedRegion].compactMap(\.self) + model.lassoed),
                    flashing: model.flashing,
                    onTap: tap,
                    onLasso: isWide ? { regions in lasso(regions) } : nil,
                    popoverRegion: isWide ? $popoverRegion : nil
                ) { _ in
                    assignControls
                        .padding()
                        .frame(width: 320)
                        .presentationCompactAdaptation(.popover)
                }
            }
            .background(.background.secondary)
            .overlay(alignment: .bottom) {
                if !isWide, model.selectedRegion != nil {
                    assignControls
                        .padding(14)
                        .glassEffect(in: .rect(cornerRadius: 22))
                        .padding(10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.selectedRegion)
        }
    }

    private var aspectRatio: CGFloat {
        guard let image = images[shownPage], image.size.height > 0 else { return 3 / 4 }
        return image.size.width / image.size.height
    }

    /// A label where a run of one kind starts, numbering the steps.
    private func regionLabel(_ region: ReviewRegion, _ role: RegionRole?) -> String? {
        let onPage = model.regions.filter { $0.page == region.page && !$0.isPhoto }
        if region.isPhoto {
            if let step = model.stepNumber(forPhoto: region.id) { return "Step \(step) Photo" }
            return role?.label ?? "Photo"
        }
        guard let role else {
            return "Unassigned"
        }
        if role == .furniture || role == .ignore { return nil }
        if role == .step {
            // "Step 2" on a step's first region; a paragraph it runs on into carries no label.
            return model.recipe.steps.firstIndex { $0.regions.first == region.id }.map { "Step \($0 + 1)" }
        }
        if let index = onPage.firstIndex(where: { $0.id == region.id }), index > 0, onPage[index - 1].role == role, role != .step {
            return nil
        }
        return role.label
    }

    private func tap(_ region: ReviewRegion) {
        editingFocus = nil
        model.lassoed = []
        if region.recipe != nil, region.recipe != model.current, model.recipes.indices.contains(region.recipe!) {
            // A tap on the other recipe's region shows that recipe.
            model.current = region.recipe!
        }
        model.selectedRegion = model.selectedRegion == region.id ? nil : region.id
        popoverRegion = isWide ? model.selectedRegion : nil
    }

    private func lasso(_ regions: [ReviewRegion]) {
        model.lassoed = regions.map(\.id)
        model.selectedRegion = regions.first?.id
        popoverRegion = regions.first?.id
    }

    /// What the cook can make the region: the floating segmented control of 03 §3.6.
    @ViewBuilder
    private var assignControls: some View {
        let ids = model.lassoed.isEmpty ? [model.selectedRegion].compactMap(\.self) : model.lassoed
        let regions = ids.compactMap(model.region)
        let photos = regions.allSatisfy(\.isPhoto)
        let current = regions.count == 1 ? regions.first.flatMap(model.shownRole(of:)) : nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(regions.count > 1 ? "\(regions.count) regions" : (photos ? "Printed photo" : (regions.first?.text ?? "")))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Done", systemImage: "xmark") {
                    model.selectedRegion = nil
                    model.lassoed = []
                    popoverRegion = nil
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            let choices = photos ? RegionRole.photoChoices : RegionRole.textChoices
            if isWide {
                // The popover has the height: every choice at once.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(choices) { role in choice(role, ids: ids, current: current) }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(choices) { role in choice(role, ids: ids, current: current) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private func choice(_ role: RegionRole, ids: [Int], current: RegionRole?) -> some View {
        if role == .stepPhoto {
            stepPhotoMenu(ids, isCurrent: current == .stepPhoto)
        } else {
            roleButton(role, isCurrent: current == role || (role == .ingredient && current == .ingredientGroup)) {
                withAnimation { model.assign(ids, to: role) }
                popoverRegion = nil
            }
        }
    }

    private func roleButton(_ role: RegionRole, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(role.label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isCurrent ? AnyShapeStyle(role.color) : AnyShapeStyle(role.color.opacity(0.18)), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// Step Photo asks which step (ux-notes row 62): the one beside the photo first.
    private func stepPhotoMenu(_ ids: [Int], isCurrent: Bool) -> some View {
        let steps = model.recipe.steps
        let suggested = ids.first.flatMap { model.candidateSteps[$0] }
        return Menu {
            if steps.isEmpty {
                Text("No steps to attach it to")
            }
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                Button {
                    withAnimation { model.assign(ids, to: .stepPhoto, step: step.id) }
                    popoverRegion = nil
                } label: {
                    Text("Step \(index + 1)\(step.id == suggested ? " (beside it)" : "")")
                    Text(step.text).lineLimit(1)
                }
            }
        } label: {
            Text(RegionRole.stepPhoto.label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isCurrent ? AnyShapeStyle(Color.pink) : AnyShapeStyle(Color.pink.opacity(0.18)), in: .capsule)
        }
        .disabled(steps.isEmpty)
    }

    // MARK: - The recipe

    private var structurePane: some View {
        List {
            Section {
                if model.recipes.count > 1 {
                    Picker("Recipe", selection: $model.current) {
                        ForEach(model.recipes.indices, id: \.self) { index in
                            Text(model.recipes[index].displayTitle).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                reasonLine
                if model.recipe.isSkipped {
                    Label("Skipped: this recipe won't be saved. More → Include This Recipe brings it back.", systemImage: "minus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            // The banner's cross-references (03 §3.6, 02 Flow C step 6): a card per pointer.
            if !model.recipe.pointers.isEmpty {
                Section {
                    ForEach(model.recipe.pointers) { pointer in
                        PointerCard(pointer: pointer, book: book, stored: stored) { choice in
                            withAnimation { model.setPointerChoice(choice, for: pointer.id) }
                        }
                    }
                } header: {
                    Text(model.recipe.pointers.count == 1 ? "Cross-Reference" : "Cross-References")
                } footer: {
                    Text("Linked recipes show under Includes. A pointer stays a tappable pill in the recipe whatever you choose.")
                }
            }

            // Split into N recipes (04 §5.1 "Sub-recipes on one page"): offered when the groups
            // line up, done on Save once confirmed.
            if !model.recipe.isSkipped, let plan = RecipeSplitting.plan(for: model.recipe) {
                Section {
                    SplitOfferRow(plan: plan, split: model.recipe.split) {
                        isSplitting = true
                    } onCancel: {
                        withAnimation { model.setSplit(nil) }
                    }
                    .sheet(isPresented: $isSplitting) {
                        SplitSheet(title: model.recipe.displayTitle, plan: plan, initial: model.recipe.split) { choice in
                            withAnimation { model.setSplit(choice) }
                        }
                    }
                } footer: {
                    Text("Its ingredient groups and steps line up as components.")
                }
            }
            Section("Title") {
                if let title = model.recipe.title {
                    itemRow(title, font: .headline)
                } else {
                    emptyRow("No title read. Tap the title on the page and choose Title.")
                }
                coursePicker
            }
            if let yield = model.recipe.yield {
                Section("Yield") { itemRow(yield) }
            }
            if !model.recipe.headnote.isEmpty {
                Section("Headnote") {
                    ForEach(model.recipe.headnote) { itemRow($0, font: .subheadline, color: .secondary) }
                }
            }
            Section("Ingredients") {
                if model.recipe.ingredients.isEmpty {
                    emptyRow("No ingredients read. Tap the list on the page and choose Ingredients.")
                }
                let ingredients = model.recipe.ingredients
                ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, item in
                    if let group = item.group, index == 0 || ingredients[index - 1].group != group {
                        Text(group)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    itemRow(item)
                }
            }
            Section("Steps") {
                if model.recipe.steps.isEmpty {
                    emptyRow("No steps read. Tap a paragraph of the method and choose Step.")
                }
                ForEach(Array(model.recipe.steps.enumerated()), id: \.element.id) { index, item in
                    itemRow(item, number: index + 1, photoCount: model.recipe.stepPhotos.values.count { $0 == item.id })
                }
            }
            if !model.recipe.notes.isEmpty {
                Section("Notes") {
                    ForEach(model.recipe.notes) { itemRow($0, font: .subheadline) }
                }
            }
            if model.regions.contains(where: { $0.isPhoto && model.isInCurrentRecipe($0) }) {
                Section {
                    Text(model.recipe.cover == nil && model.recipe.stepPhotos.isEmpty
                         ? "Printed photos stay with the page. Tap one to make it a step photo or the cover."
                         : "\(photoSummary). Printed photos stay with the page unless you tap one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Photos")
                }
            }
        }
        .listStyle(.insetGrouped)
        .opacity(model.recipe.isSkipped ? 0.5 : 1)
        .animation(.default, value: model.recipe)
    }

    /// The course it is saved with (ux-notes row 73): the last chosen for the book to begin with.
    private var coursePicker: some View {
        Picker("Course", selection: Binding { model.recipe.course } set: { course in
            withAnimation { model.setCourse(course) }
        }) {
            Text("None").tag(String?.none)
            ForEach(courseOptions, id: \.self) { course in
                Text(course).tag(Optional(course))
            }
        }
    }

    private var courseOptions: [String] {
        var options = RecipeCourse.standard
        if let course = model.recipe.course, !options.contains(course) { options.append(course) }
        return options
    }

    private var photoSummary: String {
        var parts: [String] = []
        if model.recipe.cover != nil { parts.append("A cover") }
        let count = model.recipe.stepPhotos.count
        if count > 0 { parts.append(count == 1 ? "1 step photo" : "\(count) step photos") }
        return parts.joined(separator: " and ")
    }

    /// Why review was asked: the one-time sentence for a book's first recipe or a new layout (03
    /// §3.6), else the reasons in a few words.
    @ViewBuilder
    private var reasonLine: some View {
        let reasons = model.recipe.reasons
        if showsExplanation, reasons.contains(where: ScanGate.forcing.contains) {
            Label("Check this one so Codex learns how this book lays out a recipe.", systemImage: "graduationcap")
                .font(.subheadline)
        } else if !reasons.isEmpty {
            Label(reasonText(reasons), systemImage: "checkmark.rectangle.stack")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func reasonText(_ reasons: [ReviewReason]) -> String {
        reasons.map { reason in
            switch reason {
            case .firstRecipeOfBook: "The first recipe from \(bookTitle ?? "this book")"
            case .unseenLayout: bookTitle == nil ? "A page from no book is always checked" : "A layout not yet confirmed for \(bookTitle!)"
            default: reason.label.prefix(1).uppercased() + reason.label.dropFirst()
            }
        }
        .joined(separator: "; ") + "."
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func itemRow(_ item: ReviewItem, number: Int? = nil, font: Font = .body, color: Color = .primary, photoCount: Int = 0) -> some View {
        if model.editingItem == item.id {
            TextField("Text", text: $editingText, axis: .vertical)
                .font(font)
                .focused($editingFocus, equals: item.id)
                .submitLabel(.done)
                .onSubmit { editingFocus = nil }
                // Return ends the edit (ux-notes row 70). A field that wraps takes Return as a line
                // break, so a break typed (or pasted) comes out and the edit ends: an ingredient is
                // one line, and a step stays one paragraph.
                .onChange(of: editingText) { _, text in
                    guard text.contains(where: \.isNewline) else { return }
                    editingText = text.split(whereSeparator: \.isNewline).joined(separator: " ")
                    editingFocus = nil
                }
        } else {
            Button {
                tap(item)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let number {
                        Text("\(number)")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                            .frame(minWidth: 20, alignment: .trailing)
                    }
                    Text(item.text)
                        .font(font)
                        .foregroundStyle(color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if photoCount > 0 {
                        Image(systemName: "photo")
                            .foregroundStyle(.pink)
                            .accessibilityLabel(photoCount == 1 ? "With a step photo" : "With \(photoCount) step photos")
                    }
                    if item.regions.isEmpty, model.recipe.method == .model {
                        Image(systemName: "apple.intelligence")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Read by Apple Intelligence")
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(lastTapped == item.id && !model.flashing.isEmpty ? Color.accentColor.opacity(0.12) : nil)
            .accessibilityHint("Shows where it is on the page. Tap again to correct the wording.")
            .contextMenu {
                Button("Edit Text", systemImage: "pencil") { beginEdit(item) }
                Button("Remove", systemImage: "trash", role: .destructive) { withAnimation { model.remove(item) } }
            }
            .swipeActions {
                Button("Remove", systemImage: "trash", role: .destructive) { withAnimation { model.remove(item) } }
            }
        }
    }

    /// The first tap flashes the item's source; a second corrects its wording.
    private func tap(_ item: ReviewItem) {
        if lastTapped == item.id {
            beginEdit(item)
            return
        }
        lastTapped = item.id
        model.selectedRegion = nil
        model.flash(item)
        if let first = item.regions.first.flatMap(model.region) {
            shownPage = first.page
            let rects = item.regions.compactMap(model.region).filter { $0.page == first.page }.map(\.rect)
            focusRect = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        }
    }

    private func beginEdit(_ item: ReviewItem) {
        editingText = item.text
        model.editingItem = item.id
        Task {
            await Task.yield()
            editingFocus = item.id
        }
    }

    private func commitEdit(_ id: ReviewItem.ID) {
        let text = editingText.trimmed
        if !text.isEmpty { model.edit(id, text: text) }
        if model.editingItem == id { model.editingItem = nil }
        lastTapped = nil
    }

    // MARK: - Images

    private func loadImages() async {
        for page in model.pages where images[page.id] == nil {
            if let image = await ScanImage.upright(page, maxPixelSize: 2_400) {
                images[page.id] = UIImage(cgImage: image)
            }
        }
    }
}
