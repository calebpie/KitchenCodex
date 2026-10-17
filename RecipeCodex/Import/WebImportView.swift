import Capture
import Intelligence
import RecipeModel
import SwiftData
import SwiftUI

/// Recipes → Add → Import from Web: paste a link, Recipe Codex fetches the page as Safari would, reads
/// the recipe with the same importer as the Share Extension, and shows the import preview (03 §3.4)
/// for a check before saving through the manual-entry path.
struct WebImportView: View {
    /// Called with the saved recipe just before the sheet dismisses, so Recipes can open it.
    var onSaved: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    enum Phase: Equatable {
        case entry
        case working(String)
        case preview
        case failed(String)
    }

    @State private var address = ""
    @State private var phase: Phase = .entry
    @State private var imported: ImportedRecipe?
    @State private var draft = RecipeDraft()
    @State private var coverPreview: UIImage?
    @State private var isLoadingCover = false
    @State private var isConfirmingDiscard = false
    @State private var work: Task<Void, Never>?
    /// The deterministic reading while the model works, so the cook can skip the wait.
    @State private var pageReading: ImportedRecipe?
    @State private var modelWork: Task<ImportedRecipe?, Never>?
    /// What a failed import still knows, for "Add Manually Instead".
    @State private var fallbackTitle = ""
    @State private var fallbackURL: URL?
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .entry: entry
                case let .working(message): working(message)
                case .preview: preview
                case let .failed(message): failure(message)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(phase == .preview)
        }
        .onDisappear {
            work?.cancel()
            modelWork?.cancel()
        }
    }

    private var title: String {
        switch phase {
        case .preview: imported?.method == nil ? "New Recipe" : "Import Recipe"
        default: "Import from Web"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) {
                if phase == .preview { isConfirmingDiscard = true } else { dismiss() }
            }
            .confirmationDialog("Discard this recipe?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch phase {
            case .entry:
                Button("Import") { start() }
                    .disabled(address.trimmed.isEmpty)
            case .preview:
                Button("Save", role: .confirm) { save() }
                    .disabled(!draft.canSave || isLoadingCover)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Phases

    private var entry: some View {
        Form {
            Section {
                TextField("Recipe link", text: $address, prompt: Text("https://"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($addressFocused)
                    .onSubmit(start)
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    address = WebPageFetcher.webURL(from: text)?.absoluteString ?? text
                    start()
                }
            } footer: {
                Text("Paste a link to a recipe page. Recipe Codex reads the page the way Safari shows it and finds the recipe on it.")
            }
        }
        .onAppear { addressFocused = true }
    }

    private func working(_ message: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if modelWork != nil, pageReading != nil {
                Button("Use Page Reading", action: skipModel)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Import", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Add Manually Instead") { addManually() }
                .buttonStyle(.borderedProminent)
            Button("Try Again") { phase = .entry }
        }
    }

    private var preview: some View {
        Form {
            if let imported {
                Section {
                    ImportSummaryView(recipe: liveSummary(of: imported), cover: coverPreview, showsTitle: false)
                        .overlay {
                            if isLoadingCover { ProgressView() }
                        }
                }
            }

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

            Section {
                PlaceholderTextEditor(text: $draft.ingredientsText, placeholder: "2 cups flour\n1 1/2 tsp kosher salt")
                    .frame(minHeight: 140)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Ingredients")
            } footer: {
                Text("One ingredient per line, as the page wrote them. Check how each one reads below.")
            }

            if !draft.parsedIngredients.isEmpty {
                Section("Reads As") {
                    ForEach(Array(draft.parsedIngredients.enumerated()), id: \.offset) { _, parsed in
                        ParsedIngredientRow(parsed: parsed)
                    }
                }
            }

            Section {
                PlaceholderTextEditor(text: $draft.stepsText, placeholder: "Whisk the dry ingredients.\n\nBeat in the eggs one at a time.")
                    .frame(minHeight: 180)
            } header: {
                Text("Steps")
            } footer: {
                Text("One step per paragraph.")
            }

            if let url = imported?.sourceURL {
                Section("Source") {
                    Link(destination: url) {
                        Label(url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString, systemImage: "safari")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The summary follows the edits, so its counts stay true.
    private func liveSummary(of imported: ImportedRecipe) -> ImportedRecipe {
        var summary = imported
        summary.title = draft.title
        summary.ingredients = draft.parsedIngredients.map(\.rawText)
        summary.steps = StepSplitter.steps(from: draft.stepsText)
        return summary
    }

    private var courseOptions: [String] {
        var options = RecipeCourse.standard
        if let course = draft.course, !options.contains(course) { options.append(course) }
        return options
    }

    // MARK: - Importing

    private func start() {
        guard let url = WebPageFetcher.webURL(from: address) else {
            fallbackTitle = ""
            fallbackURL = nil
            phase = .failed(WebImportError.invalidURL.localizedDescription)
            return
        }
        addressFocused = false
        work?.cancel()
        work = Task { await importRecipe(from: url) }
    }

    private func importRecipe(from url: URL) async {
        fallbackTitle = ""
        fallbackURL = url
        phase = .working("Reading the page…")
        do {
            let page = try await WebPageFetcher().fetchPage(url)
            fallbackURL = page.url
            let extraction = await Self.extract(page)
            fallbackTitle = extraction.pageTitle
            var result = extraction.recipe

            let importer = WebRecipeImporter(structurer: OnDeviceRecipeStructurer())
            if importer.canRefine(extraction) {
                // HIG Generative AI: say specifically what the model is doing.
                phase = .working("Reading ingredients…")
                pageReading = extraction.recipe
                let task = Task { await importer.refine(extraction) }
                modelWork = task
                let refined = await task.value
                // Skipped: the page reading is already showing.
                guard modelWork != nil else { return }
                modelWork = nil
                pageReading = nil
                if let refined { result = refined }
            }
            try Task.checkCancellation()
            guard let result else { throw WebImportError.noRecipeFound }
            show(result)
        } catch is CancellationError {
            return
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Parsing a large page takes tens of milliseconds; keep it off the main actor.
    @concurrent
    nonisolated private static func extract(_ page: FetchedPage) async -> WebPageExtraction {
        WebRecipeImporter.extract(html: page.html, url: page.url)
    }

    private func show(_ result: ImportedRecipe) {
        imported = result
        draft = RecipeDraft(imported: result)
        coverPreview = nil
        phase = .preview
        guard result.imageURL != nil else { return }
        isLoadingCover = true
        Task {
            let cover = await RecipeDraft.coverPhoto(for: result)
            if imported == result {
                draft.photo = cover.change
                coverPreview = cover.preview
            }
            isLoadingCover = false
        }
    }

    private func skipModel() {
        guard let reading = pageReading else { return }
        modelWork?.cancel()
        modelWork = nil
        pageReading = nil
        show(reading)
    }

    private func addManually() {
        let manual = ImportedRecipe.manual(title: fallbackTitle, url: fallbackURL)
        imported = manual
        draft = RecipeDraft(imported: manual)
        coverPreview = nil
        phase = .preview
    }

    private func save() {
        guard let imported else { return }
        let recipe = draft.saveImport(imported, in: modelContext)
        onSaved(recipe)
        dismiss()
    }
}
