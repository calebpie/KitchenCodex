import Capture
import Intelligence
import OSLog
import RecipeModel
import SwiftData
import SwiftUI

/// Recipes → Add → Import from Web: paste a link, Kitchen Codex fetches the page as Safari would, reads
/// the recipe with the same importer as the Share Extension, and shows the import preview (03 §3.4)
/// for a check before saving through the manual-entry path. A page whose fetched HTML holds no recipe
/// is rendered in a hidden web view and read again (`RenderedPageLoader`).
///
/// A complete reading (title, ingredients, steps) shows at once. The on-device model is asked only
/// when `WebRecipeImporter.wantsModel` says so: with nothing complete to show, the sheet waits on
/// "Reading ingredients…" (Use Page Reading skips it); with a page-text reading that had no headings
/// to go by, the preview shows it while the model reads, says so in a row, and takes the model's
/// reading in place if the cook hasn't edited the preview by then.
///
/// A page with Article markup and no recipe (02 §4.2) offers Save as Reference: its title, author
/// and headed sections save as reference reading in Pantry → References.
struct WebImportView: View {
    /// Called with the saved recipe just before the sheet dismisses, so Recipes can open it.
    var onSaved: (Recipe) -> Void
    /// Called with the saved reference just before the sheet dismisses.
    var onSavedReference: ((Reference) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    enum Phase: Equatable {
        case entry
        case working(String)
        case preview
        /// An article, not a recipe: Save as Reference.
        case reference
        case failed(String)
    }

    @State private var address = ""
    @State private var phase: Phase = .entry
    @State private var imported: ImportedRecipe?
    /// The article on a page that holds no recipe.
    @State private var article: ImportedReference?
    @State private var draft = RecipeDraft()
    @State private var coverPreview: UIImage?
    @State private var isLoadingCover = false
    @State private var isConfirmingDiscard = false
    @State private var work: Task<Void, Never>?
    /// The deterministic reading while the model works, so the cook can skip the wait.
    @State private var pageReading: ImportedRecipe?
    @State private var modelWork: Task<ImportedRecipe?, Never>?
    /// The preview shows a page reading while the model reads the page.
    @State private var isRefining = false
    /// What a failed import still knows, for "Add Manually Instead".
    @State private var fallbackTitle = ""
    @State private var fallbackURL: URL?
    @FocusState private var addressFocused: Bool
    /// When the current import started, for the timing in the log (02 Flow A: 2 to 6 seconds).
    @State private var importStarted: ContinuousClock.Instant?
    /// Split into N recipes, once the cook confirmed it (04 §5.1 "Sub-recipes on one page").
    @State private var split: SplitChoice?
    @State private var isSplitting = false

    private static let logger = Logger(subsystem: "com.calebpietrafesa.KitchenCodex", category: "import")

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .entry: entry
                case let .working(message): working(message)
                case .preview: preview
                case .reference: referencePreview
                case let .failed(message): failure(message)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(phase == .preview || phase == .reference)
        }
        .onDisappear {
            work?.cancel()
            modelWork?.cancel()
        }
    }

    private var title: String {
        switch phase {
        case .preview: imported?.method == nil ? "New Recipe" : "Import Recipe"
        case .reference: "Save as Reference"
        default: "Import from Web"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) {
                if phase == .preview || phase == .reference { isConfirmingDiscard = true } else { dismiss() }
            }
            // Escape cancels the sheet (03 §4, ux-notes row 43).
            .keyboardShortcut(.cancelAction)
            .confirmationDialog(phase == .reference ? "Discard this reference?" : "Discard this recipe?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
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
            case .reference:
                Button("Save", role: .confirm) { saveReference() }
                    .disabled(article?.title.trimmed.isEmpty != false)
            default:
                EmptyView()
            }
        }
    }

    /// The article's title, source and sections, read-only; Save keeps it as a Reference.
    private var referencePreview: some View {
        Form {
            if let article {
                Section {
                    ReferenceSummaryView(reference: article)
                }
                ForEach(Array(article.sections.enumerated()), id: \.offset) { _, section in
                    Section {
                        Text(section.body)
                            .lineLimit(6)
                            .font(.callout)
                    } header: {
                        if !section.heading.isEmpty { Text(section.heading) }
                    }
                }
                if let url = article.sourceURL {
                    Section("Source") {
                        Link(destination: url) {
                            Label(url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString, systemImage: "safari")
                        }
                    }
                }
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
                Text("Paste a link to a recipe page. Kitchen Codex reads the page the way Safari shows it and finds the recipe on it.")
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
                    if isRefining {
                        // HIG Generative AI: say specifically what the model is doing.
                        Label {
                            Text("Reading ingredients…")
                        } icon: {
                            ProgressView()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Apple Intelligence is reading the ingredients. The page reading is shown until it finishes.")
                    }
                }
            }

            // Its ingredient groups and step groups line up: offered, never done unasked.
            if let plan = RecipeSplitting.plan(for: draft, imported: imported) {
                Section {
                    SplitOfferRow(plan: plan, split: split) {
                        isSplitting = true
                    } onCancel: {
                        split = nil
                    }
                    .sheet(isPresented: $isSplitting) {
                        SplitSheet(title: draft.title.trimmed.isEmpty ? "This recipe" : draft.title, plan: plan, initial: split) { split = $0 }
                    }
                } footer: {
                    Text("This page's ingredient groups and steps line up as separate recipes.")
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
                    ReadsAsRows(draft: draft)
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
        summary.steps = StepSplitter.steps(from: draft.stepsText).map { ImportedStep(text: $0) }
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
        importStarted = .now
        fallbackTitle = ""
        fallbackURL = url
        phase = .working("Reading the page…")
        do {
            let page = try await WebPageFetcher().fetchPage(url)
            fallbackURL = page.url
            var extraction = await Self.extract(page)
            if extraction.recipe == nil, let rendered = await render(page) {
                extraction = rendered
            }
            fallbackTitle = extraction.pageTitle
            var result = extraction.recipe

            let importer = WebRecipeImporter(structurer: OnDeviceRecipeStructurer())
            if let reading = result, WebRecipeImporter.isComplete(reading) {
                // Shown at once; the model, when asked, refines it in place (Flow A).
                try Task.checkCancellation()
                show(reading)
                if importer.canRefine(extraction) { await refine(reading, from: extraction, with: importer) }
                return
            }
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
            guard let result else {
                // No recipe, but an article (02 §4.2): offered as reference reading.
                if let found = extraction.article {
                    logTiming("article shown", for: ImportedRecipe(title: found.title))
                    article = found
                    phase = .reference
                    return
                }
                throw WebImportError.noRecipeFound
            }
            show(result)
        } catch is CancellationError {
            return
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// The model reads the page while the preview shows `reading`. Its reading replaces the preview
    /// only while the cook hasn't changed anything; Save before then keeps the page reading.
    private func refine(_ reading: ImportedRecipe, from extraction: WebPageExtraction, with importer: WebRecipeImporter) async {
        isRefining = true
        let task = Task { await importer.refine(extraction) }
        modelWork = task
        let refined = await task.value
        // Saved or dismissed while the model read.
        guard modelWork != nil else { return }
        modelWork = nil
        isRefining = false
        guard let refined else {
            Self.logger.info("Import from Web: kept the page reading; the model's was missing or dropped lines")
            return
        }
        guard imported == reading else { return }
        var untouched = draft
        untouched.photo = .unchanged
        guard untouched == RecipeDraft(imported: reading) else {
            Self.logger.info("Import from Web: kept the cook's edits over the model's reading")
            return
        }
        logTiming("model reading shown", for: refined)
        let photo = draft.photo
        imported = refined
        draft = RecipeDraft(imported: refined)
        // The model keeps the page's cover; the one already downloaded stays.
        draft.photo = photo
    }

    /// A JavaScript-built page (ChefSteps) arrives from the fetch as an empty shell. Render it in a web
    /// view, wait for its scripts, and read the DOM again, as the Share Extension gets it from Safari.
    /// Nil when rendering fails or finds nothing the fetch didn't; the fetch's reading stands then.
    private func render(_ page: FetchedPage) async -> WebPageExtraction? {
        phase = .working("Loading the full page…")
        var reading: WebPageExtraction?
        do {
            _ = try await RenderedPageLoader.render(page.url) { rendered in
                let extraction = await Self.extract(html: rendered.html, url: rendered.url)
                reading = extraction
                return extraction.recipe != nil
            }
        } catch {
            return nil
        }
        guard let reading, !Task.isCancelled else { return nil }
        // Keep the rendering when it found the recipe or an article, or at least more text for
        // the model to read.
        return reading.recipe != nil || reading.article != nil || reading.recipeText.count > 0 ? reading : nil
    }

    /// Parsing a large page takes tens of milliseconds; keep it off the main actor.
    @concurrent
    nonisolated private static func extract(_ page: FetchedPage) async -> WebPageExtraction {
        WebRecipeImporter.extract(html: page.html, url: page.url)
    }

    @concurrent
    nonisolated private static func extract(html: String, url: URL) async -> WebPageExtraction {
        WebRecipeImporter.extract(html: html, url: url)
    }

    private func show(_ result: ImportedRecipe) {
        logTiming("preview shown", for: result)
        imported = result
        draft = RecipeDraft(imported: result)
        split = nil
        coverPreview = nil
        phase = .preview
        guard result.imageURL != nil else { return }
        isLoadingCover = true
        Task {
            let cover = await RecipeDraft.coverPhoto(for: result)
            // By its link: the model's reading, taken in place meanwhile, keeps the same cover.
            if imported?.imageURL == result.imageURL {
                draft.photo = cover.change
                coverPreview = cover.preview
            }
            isLoadingCover = false
        }
    }

    /// "Import from Web: preview shown after 0.42 s (jsonLD, 8 ingredients, 5 steps)".
    private func logTiming(_ event: String, for recipe: ImportedRecipe) {
        guard let importStarted else { return }
        let seconds = (ContinuousClock.now - importStarted).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2)))
        Self.logger.info("Import from Web: \(event, privacy: .public) after \(seconds, privacy: .public) (\(recipe.method?.rawValue ?? "manual", privacy: .public), \(recipe.ingredients.count) ingredients, \(recipe.steps.count) steps)")
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

    private func saveReference() {
        guard let article else { return }
        let reference = article.save(in: modelContext)
        onSavedReference?(reference)
        dismiss()
    }

    private func save() {
        guard let imported else { return }
        // Saving keeps what the preview shows; a model still reading is no longer needed.
        modelWork?.cancel()
        modelWork = nil
        let recipe = split.flatMap { RecipeSplitting.saveImport(draft, imported: imported, choice: $0, in: modelContext) }
            ?? draft.saveImport(imported, in: modelContext)
        onSaved(recipe)
        dismiss()
    }
}
