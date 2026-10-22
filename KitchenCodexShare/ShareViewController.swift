import Capture
import Intelligence
import OSLog
import RecipeModel
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Entry point for "Share → Kitchen Codex" (Flow A). Reads the shared page (Safari hands over the
/// rendered DOM through GetPageSource.js; other apps share a link, which is fetched), imports it
/// with the same importer as the app, shows a compact preview, and saves into the App Group store.
/// A complete reading shows at once and the on-device model refines it in place with the same
/// "Reading ingredients…" row as the app (ux-notes row 44); an Article page with no recipe offers
/// Save as Reference (02 §4.2). There is no Open in app button: iOS 27 gives a share extension no
/// supported way to open its containing app (`NSExtensionContext.open` is for Today widgets), and
/// the responder-chain workaround is not used.
final class ShareViewController: UIViewController {
    private let model = ShareImportModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.onFinish = { [weak self] saved in
            if saved { self?.finish() } else { self?.cancel() }
        }
        let host = UIHostingController(rootView: SharePreviewView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let context = extensionContext
        Task { [model] in
            await model.start(with: SharedPage.load(from: context))
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}

nonisolated private let log = Logger(subsystem: "com.calebpietrafesa.KitchenCodex.Share", category: "import")

/// `NSItemProvider.loadItem(forTypeIdentifier:options:completionHandler:)` without its iOS 27
/// deprecation warning; see `SharedPage.javaScriptResults(from:)`.
private protocol PropertyListItemLoading {
    func loadItem(forTypeIdentifier typeIdentifier: String, options: [AnyHashable: Any]?, completionHandler: NSItemProvider.CompletionHandler?)
}

extension NSItemProvider: PropertyListItemLoading {}

/// What the host app shared.
struct SharedPage: Sendable {
    var url: URL?
    /// The rendered page, when Safari ran the preprocessing script.
    var html: String?
    var title: String?

    static func load(from context: NSExtensionContext?) async -> SharedPage {
        var page = SharedPage()
        let providers = (context?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        for provider in providers {
            log.debug("Shared attachment types: \(provider.registeredTypeIdentifiers, privacy: .public)")
            if page.html == nil, provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
               let results = await javaScriptResults(from: provider) {
                page.html = results.html
                page.title = results.title
                page.url = page.url ?? results.url.flatMap(URL.init(string:))
            }
            if page.url == nil, provider.canLoadObject(ofClass: URL.self), let url = await loadURL(from: provider) {
                page.url = url
            }
            if page.url == nil, provider.canLoadObject(ofClass: String.self), let text = await loadText(from: provider) {
                page.url = WebPageFetcher.webURL(from: text)
            }
        }
        return page
    }

    /// The dictionary GetPageSource.js passed to `completionFunction`.
    ///
    /// Safari registers it as a bare NSDictionary under "com.apple.property-list", which only the
    /// item-loading API returns (a data representation comes back empty). That API is deprecated in
    /// iOS 27 with no replacement for JavaScript preprocessing results, so it is called through
    /// `PropertyListItemLoading` to keep the build free of warnings.
    private static func javaScriptResults(from provider: NSItemProvider) async -> (html: String?, title: String?, url: String?)? {
        await withCheckedContinuation { continuation in
            (provider as any PropertyListItemLoading).loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { item, error in
                if let error { log.error("Property list load failed: \(error.localizedDescription, privacy: .public)") }
                guard let dictionary = item as? NSDictionary,
                      let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (results["html"] as? String, results["title"] as? String, results["url"] as? String))
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }
}

@Observable
final class ShareImportModel {
    enum Phase: Equatable {
        case reading(String)
        case ready
        /// An article, not a recipe: Save keeps it as a Reference.
        case readyReference
        case saving
        case failed(String)
    }

    var phase: Phase = .reading("Reading the page…")
    var recipe: ImportedRecipe?
    /// The article on a page that holds no recipe.
    var reference: ImportedReference?
    /// A reference already saved from the article's link (ux-notes row 112): the preview says so,
    /// and Save becomes Save Again. The extension has no way to open the app (slice 7), so no Open.
    var isReferenceSaved = false
    var cover: UIImage?
    var isLoadingCover = false
    /// The preview shows a page reading while the model reads the page (ux-notes row 44).
    var isRefining = false
    var onFinish: ((Bool) -> Void)?
    private var photo: RecipeDraft.PhotoChange = .unchanged
    /// The deterministic reading while the model works, so the cook can skip the wait.
    private(set) var pageReading: ImportedRecipe?
    private var modelWork: Task<ImportedRecipe?, Never>?

    func start(with shared: SharedPage) async {
        guard let url = shared.url else {
            phase = .failed("Nothing to import was shared. Share a recipe page from Safari.")
            return
        }
        do {
            let html: String
            let pageURL: URL
            if let rendered = shared.html {
                log.info("Rendered page from Safari: \(rendered.utf8.count) bytes")
                html = rendered
                pageURL = url
            } else {
                let page = try await WebPageFetcher().fetchPage(url)
                html = page.html
                pageURL = page.url
            }
            let extraction = await Self.extract(html: html, url: pageURL)
            var result = extraction.recipe
            let importer = WebRecipeImporter(structurer: OnDeviceRecipeStructurer())
            if let reading = result, WebRecipeImporter.isComplete(reading) {
                // Shown at once; the model, when asked, refines it in place (Flow A, row 44).
                log.info("Imported by \(reading.method?.rawValue ?? "-", privacy: .public): \(reading.ingredients.count) ingredients, \(reading.steps.count) steps")
                await show(reading)
                if importer.canRefine(extraction) { await refine(reading, from: extraction, with: importer) }
                return
            }
            if importer.canRefine(extraction) {
                // HIG Generative AI: specific progress text while the model works.
                phase = .reading("Reading ingredients…")
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
            guard let result else {
                // No recipe, but an article (02 §4.2): offered as reference reading.
                if let article = extraction.article {
                    log.info("Article found: \(article.sections.count) sections")
                    reference = article
                    if let container = try? RecipeStore.makeContainer() {
                        isReferenceSaved = article.existing(in: ModelContext(container)) != nil
                    }
                    phase = .readyReference
                    return
                }
                throw WebImportError.noRecipeFound
            }
            log.info("Imported by \(result.method?.rawValue ?? "-", privacy: .public): \(result.ingredients.count) ingredients, \(result.steps.count) steps")
            await show(result)
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// The model reads the page while the preview shows `reading`; its reading replaces the
    /// preview when it does better (the extension edits nothing, so nothing of the cook's is lost).
    private func refine(_ reading: ImportedRecipe, from extraction: WebPageExtraction, with importer: WebRecipeImporter) async {
        isRefining = true
        let task = Task { await importer.refine(extraction) }
        modelWork = task
        let refined = await task.value
        // Saved or cancelled while the model read.
        guard modelWork != nil else { return }
        modelWork = nil
        isRefining = false
        guard let refined, recipe == reading, phase == .ready else {
            log.info("Kept the page reading; the model's was missing or dropped lines")
            return
        }
        log.info("Model reading shown: \(refined.ingredients.count) ingredients, \(refined.steps.count) steps")
        // The model keeps the page's cover; the one already downloaded stays.
        recipe = refined
    }

    private func show(_ result: ImportedRecipe) async {
        recipe = result
        phase = .ready
        guard result.imageURL != nil else { return }
        isLoadingCover = true
        let downloaded = await RecipeDraft.coverPhoto(for: result)
        photo = downloaded.change
        cover = downloaded.preview
        isLoadingCover = false
    }

    var canSkipModel: Bool { modelWork != nil && pageReading != nil }

    func skipModel() {
        guard let reading = pageReading else { return }
        modelWork?.cancel()
        modelWork = nil
        pageReading = nil
        Task { await show(reading) }
    }

    @concurrent
    nonisolated private static func extract(html: String, url: URL) async -> WebPageExtraction {
        WebRecipeImporter.extract(html: html, url: url)
    }

    func save() {
        guard recipe != nil || reference != nil else { return }
        // Saving keeps what the preview shows; a model still reading is no longer needed.
        modelWork?.cancel()
        modelWork = nil
        phase = .saving
        Task {
            do {
                // The same App Group store as the app, without CloudKit; the app syncs what lands here.
                let container = try RecipeStore.makeContainer()
                let context = ModelContext(container)
                if let recipe {
                    var draft = RecipeDraft(imported: recipe)
                    draft.photo = photo
                    draft.saveImport(recipe, in: context)
                } else if let reference {
                    // Its photos are downloaded first, so they are saved before the sheet closes.
                    await reference.save(in: context)
                }
                // `saveImport` saves quietly; a second save surfaces a failure instead of losing the recipe.
                try context.save()
                onFinish?(true)
            } catch {
                phase = .failed("Couldn't save to your library. \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        modelWork?.cancel()
        onFinish?(false)
    }
}

/// The compact preview from Flow A step 2 and 03 §3.4: cover, title, source, counts, status, Save.
struct SharePreviewView: View {
    let model: ShareImportModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case let .reading(message):
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if model.canSkipModel {
                            Button("Use Page Reading") { model.skipModel() }
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready, .saving:
                    if let recipe = model.recipe {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ImportSummaryView(recipe: recipe, cover: model.cover)
                                    .overlay(alignment: .top) {
                                        if model.isLoadingCover {
                                            ProgressView().padding(.top, 80)
                                        }
                                    }
                                if model.isRefining {
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
                            .padding()
                        }
                    } else if let reference = model.reference {
                        // A reference saving: its photos download first.
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ReferenceSummaryView(reference: reference, isAlreadySaved: model.isReferenceSaved)
                                Label {
                                    Text(reference.figures.isEmpty ? "Saving…" : "Saving its photos…")
                                } icon: {
                                    ProgressView()
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                    }
                case .readyReference:
                    if let reference = model.reference {
                        ScrollView {
                            ReferenceSummaryView(reference: reference, isAlreadySaved: model.isReferenceSaved)
                                .padding()
                        }
                    }
                case let .failed(message):
                    ContentUnavailableView {
                        Label("Couldn't Import", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    }
                }
            }
            .navigationTitle(model.phase == .readyReference ? "Save Reference" : "Save Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.phase == .readyReference && model.isReferenceSaved ? "Save Again" : "Save", role: .confirm) { model.save() }
                        .disabled(!(model.phase == .ready || model.phase == .readyReference) || model.isLoadingCover)
                }
            }
        }
    }
}
