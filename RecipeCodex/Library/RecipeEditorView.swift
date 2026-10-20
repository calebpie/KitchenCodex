import Capture
import PhotosUI
import RecipeModel
import SwiftData
import SwiftUI
import Units

/// New Recipe and Edit share this form (03 §3.4). Editing saves a new version when the content changes.
/// Reviewing (from a recipe's "Check N ingredients" row) opens at the ingredients with how each line
/// was read beside the line from the page; saving, with or without changes, clears the review.
struct RecipeEditorView: View {
    let recipe: Recipe?
    var isReviewing = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var draft: RecipeDraft
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPreview: UIImage?
    @State private var isLoadingPhoto = false
    @State private var photoFailed = false
    @State private var isConfirmingDiscard = false
    private let original: RecipeDraft

    init(recipe: Recipe?, isReviewing: Bool = false) {
        self.recipe = recipe
        self.isReviewing = isReviewing && recipe != nil
        let draft = recipe.map(RecipeDraft.init(recipe:)) ?? RecipeDraft()
        _draft = State(initialValue: draft)
        original = draft
    }

    private var isEditing: Bool { recipe != nil }
    private var hasChanges: Bool { draft != original }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    photoSection

                    Section {
                        TextField("Title", text: $draft.title, axis: .vertical)
                            .font(.headline)
                        Picker("Course", selection: $draft.course) {
                            Text("None").tag(String?.none)
                            ForEach(courseOptions, id: \.self) { course in
                                Text(course).tag(Optional(course))
                            }
                        }
                    }

                    Section("Yield") {
                        NumberField(title: "Servings", text: $draft.servings)
                        TextField("Yield, like “1 loaf” or “24 cookies”", text: $draft.yieldText)
                    }

                    Section("Time") {
                        NumberField(title: "Prep", text: $draft.prepMinutes, unit: "min")
                        NumberField(title: "Cook", text: $draft.cookMinutes, unit: "min")
                        NumberField(title: "Total", text: $draft.totalMinutes, unit: "min")
                    }

                    if isReviewing, let recipe {
                        reviewSection(recipe)
                    }

                    Section {
                        PlaceholderTextEditor(text: $draft.ingredientsText, placeholder: "2 cups flour\n1 1/2 tsp kosher salt\n3 large eggs\nsalt to taste")
                            .frame(minHeight: 140)
                            // "tsp" and "tbsp" are not typos.
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("Ingredients")
                    } footer: {
                        Text("One ingredient per line. Amounts and units are read automatically so the recipe can scale. A line ending with a colon, like “For the dressing:”, starts a group.")
                    }

                    if !draft.parsedIngredients.isEmpty {
                        Section("Reads As") {
                            ReadsAsRows(draft: draft)
                        }
                    }

                    Section {
                        PlaceholderTextEditor(text: $draft.stepsText, placeholder: "Whisk the dry ingredients.\n\nBeat in the eggs one at a time.")
                            .frame(minHeight: 180)
                    } header: {
                        Text("Steps")
                    } footer: {
                        Text("One step per paragraph. Leave a blank line between steps; numbering is added for you.")
                    }

                    if let recipe, !stepPhotos(of: recipe).isEmpty {
                        stepPhotosSection(recipe)
                    }

                    Section("Notes") {
                        PlaceholderTextEditor(text: $draft.notes, placeholder: "Substitutions, timing, what to serve it with")
                            .frame(minHeight: 100)
                    }

                    if let recipe {
                        Section {
                            TextField("What changed? (optional)", text: $draft.changeSummary)
                        } header: {
                            Text("Version")
                        } footer: {
                            Text("Saving a change to the yield, times, ingredients, steps or notes creates version \(recipe.nextVersionNumber). Earlier versions are kept.")
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    guard isReviewing, let recipe else { return }
                    // Open at the first line to check, else the ingredients (03 §3.3: the row
                    // scrolls to the suspect items).
                    let target: AnyHashable = recipe.ingredientsToCheck.first.map { AnyHashable($0.persistentModelID) } ?? AnyHashable(Self.reviewSectionID)
                    Task {
                        await Task.yield()
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
            .navigationTitle(isReviewing ? "Review Recipe" : (isEditing ? "Edit Recipe" : "New Recipe"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                    // Escape cancels the sheet (03 §4, ux-notes row 43).
                    .keyboardShortcut(.cancelAction)
                    .confirmationDialog("Discard changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Reviewing can save without changes: that is the cook saying it looks right.
                    Button("Save", role: .confirm) { save() }
                        .disabled(!draft.canSave || (isEditing && !hasChanges && !isReviewing) || isLoadingPhoto)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
            .task {
                if let data = recipe?.coverImageData {
                    photoPreview = await ImageProcessing.thumbnail(from: data, maxPixelSize: 600)
                }
            }
        }
    }

    // MARK: - Photo

    private var photoSection: some View {
        Section {
            if let photoPreview {
                Image(uiImage: photoPreview)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(.rect(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .accessibilityLabel("Cover photo")
            }
            // PhotosPicker's label closure is nonisolated, so read the state here.
            let title = photoPreview == nil ? "Add Photo" : "Change Photo"
            let isLoading = isLoadingPhoto
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                HStack {
                    Label(title, systemImage: "photo")
                    if isLoading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            if photoPreview != nil {
                Button("Remove Photo", systemImage: "trash", role: .destructive) {
                    photoPreview = nil
                    photoItem = nil
                    draft.photo = recipe?.coverImageData == nil ? .unchanged : .removed
                }
            }
        } footer: {
            if photoFailed {
                Text("That photo couldn't be read. Try another.")
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        photoFailed = false
        defer { isLoadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let photo = await ImageProcessing.jpeg(from: data, maxPixelSize: 2_400, quality: 0.85),
              let cover = await ImageProcessing.jpeg(from: data, maxPixelSize: 900, quality: 0.8) else {
            photoFailed = true
            return
        }
        draft.photo = .replaced(photo: photo, cover: cover)
        photoPreview = await ImageProcessing.thumbnail(from: cover, maxPixelSize: 600)
    }

    // MARK: - Step photos

    /// Each current step that has photos, with its number.
    private func stepPhotos(of recipe: Recipe) -> [(number: Int, photos: [RecipeImage])] {
        (recipe.currentVersion?.sortedSteps ?? []).enumerated().compactMap { index, step in
            let photos = step.sortedPhotos
            return photos.isEmpty ? nil : (index + 1, photos)
        }
    }

    /// Read-only for now: taking your own step photos arrives with Cook mode (Phase 3).
    private func stepPhotosSection(_ recipe: Recipe) -> some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(stepPhotos(of: recipe), id: \.number) { entry in
                        ForEach(entry.photos) { photo in
                            VStack(spacing: 4) {
                                StepPhotoImage(image: photo, pointSize: 72)
                                    .frame(width: 72, height: 72)
                                    .clipShape(.rect(cornerRadius: 10))
                                Text("Step \(entry.number)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Photo of step \(entry.number)")
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        } header: {
            Text("Step Photos")
        } footer: {
            Text("A photo stays with its step when you edit, as long as the step's text or its place in the list stays the same.")
        }
    }

    // MARK: - Saving

    private var courseOptions: [String] {
        var options = RecipeCourse.standard
        if let course = draft.course, !options.contains(course) { options.append(course) }
        return options
    }

    private func save() {
        let saved = draft.save(to: recipe, comparedWith: original, in: modelContext)
        if isReviewing { saved.markReviewed(in: modelContext) }
        dismiss()
    }

    // MARK: - Review

    private static let reviewSectionID = "review"

    /// The stored lines as the import read them, with the page's original under each, and the page.
    private func reviewSection(_ recipe: Recipe) -> some View {
        Section {
            IngredientProvenanceRows(ingredients: recipe.currentVersion?.sortedIngredients ?? [])
            if let url = recipe.source?.url {
                Link(destination: url) {
                    Label("View Page", systemImage: "safari")
                }
            }
        } header: {
            Text("As Imported")
        } footer: {
            Text("Bold is how each line was read; under it is the line as the page wrote it. Fix a line below and it is read again. Saving marks the recipe as checked.")
        }
        .id(Self.reviewSectionID)
    }
}

/// A labelled whole-number field. Tapping anywhere in the row focuses it.
struct NumberField: View {
    let title: String
    @Binding var text: String
    var unit: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, text: $text, prompt: Text("–"))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .onChange(of: text) { _, new in
                        let digits = new.filter(\.isNumber)
                        if digits != new { text = digits }
                    }
                if let unit {
                    Text(unit).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
    }
}

/// `TextEditor` with a placeholder, for the multi-line fields.
struct PlaceholderTextEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHint(placeholder)
    }
}

/// The "Reads As" rows: each parsed line, under its group heading when it has one.
struct ReadsAsRows: View {
    let draft: RecipeDraft

    var body: some View {
        let lines = draft.groupedIngredients
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            if let group = line.group, index == 0 || lines[index - 1].group != group {
                Text(group)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
            ParsedIngredientRow(parsed: line.parsed)
        }
    }
}

/// How the parser read one line: amount and unit in bold, then the item, the preparation and the
/// note with how it will read (after a comma, or in parentheses), each on its own line
/// (04 §5.1 Ingredient lines).
struct ParsedIngredientRow: View {
    let parsed: ParsedIngredient

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(amount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(parsed.item)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = parsed.note {
                    Text("Note: \(note)\(Text(verbatim: " · \(Self.formTitle(note: note, form: parsed.noteForm))").foregroundStyle(.tertiary))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var amount: String {
        guard let quantity = parsed.quantity else { return parsed.unit == .toTaste ? "to taste" : "—" }
        return Quantity(quantity, parsed.unit).formatted()
    }

    private var detail: String? {
        let parts = [parsed.preparation, parsed.isOptional ? "optional" : nil].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Where the note will sit on the recipe, as `NoteForm.suffix` places it.
    static func formTitle(note: String, form: NoteForm?) -> String {
        NoteForm.suffix(for: note, form: form).hasPrefix(",") ? "after a comma" : "in parentheses"
    }
}
