import Capture
import PhotosUI
import RecipeModel
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Recipes → Add → Scan Page (02 Flow B, 03 §3.5–3.6): the camera on a device (it opens at once, its
/// captures read as they are taken), From Photo (several pages at once, in order) or Files; the
/// processing sheet with the pipeline's real stages; the book a barcode among the pages names, or
/// Which book? when the scan did not start from one; then review where it is forced and saving
/// straight where it is not. The Simulator has no camera, so there it offers From Photo and Files.
struct ScanPageView: View {
    /// Called with the recipes saved when the sheet closes; Recipes opens one when there is one.
    var onFinish: ([Recipe]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var session: ScanSession
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isChoosingPhotos = false
    @State private var isChoosingFiles = false
    @State private var isConfirmingCancel = false
    @State private var isShowingCamera = false
    @State private var hasOpenedCamera = false
    @State private var isCameraDenied = CameraAccess.isDenied

    init(book: Book? = nil, onFinish: @escaping ([Recipe]) -> Void) {
        self.onFinish = onFinish
        _session = State(initialValue: ScanSession(book: book))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(session.phase != .choosing && session.phase != .finished)
        // The photos as taken (HEIC, full size), not a converted copy: page text is small.
        .photosPicker(isPresented: $isChoosingPhotos, selection: $photoItems, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())
        .fileImporter(isPresented: $isChoosingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { session.start(with: urls) }
        }
        .onChange(of: photoItems) { _, items in
            session.start(with: items)
        }
        .onChange(of: session.phase) { _, phase in
            // One recipe and nothing else: open it, as Import from Web does.
            guard phase == .finished, session.saved.count == 1, session.keptPages + session.discardedPages == 0 else { return }
            finish(session.saved.map(\.recipe))
        }
        .onAppear { session.modelContext = modelContext }
        // The camera's cover hides the sheet without closing it: its pages are being written.
        .onDisappear { if !isShowingCamera { session.cancel() } }
        // The camera opens with Scan Page on a device (02 Flow B step 2); Close comes back here.
        .task {
            guard !hasOpenedCamera, CameraAccess.isAvailable, !CameraAccess.isDenied else { return }
            hasOpenedCamera = true
            await openCamera()
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            PageCameraView(session: session) {
                isShowingCamera = false
                Task { await session.finishCapturing() }
            } onClose: {
                isShowingCamera = false
                session.discardCaptures()
            }
        }
    }

    /// Camera access on first use; turned off, Settings is the way back.
    private func openCamera() async {
        if await CameraAccess.request() {
            isShowingCamera = true
        } else {
            isCameraDenied = true
        }
    }

    private var title: String {
        switch session.phase {
        case .whichBook: "Which Book?"
        case .reviewing: "Review Scan"
        case .notRecipe: "Not a Recipe"
        case .finished: "Saved"
        default: "Scan Page"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .choosing:
            choosing
        case .loading:
            ProgressView("Opening the photos…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .processing:
            ScanProcessingView(session: session)
        case .whichBook:
            WhichBookView(session: session)
        case .reviewing:
            if let review = session.review {
                ScanReviewView(model: review, bookTitle: session.book?.displayTitle) {
                    Task { await session.rescan() }
                }
                .disabled(session.isSaving)
            }
        case .notRecipe:
            NotARecipeView(session: session)
        case .finished:
            ScanSummaryView(session: session) { recipe in finish([recipe]) }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't Read the Photos", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Choose Again") { session.phase = .choosing }
            }
        }
    }

    private var choosing: some View {
        Form {
            if CameraAccess.isAvailable {
                Section {
                    Button {
                        Task { await openCamera() }
                    } label: {
                        choiceLabel("Camera", detail: "Photograph the pages; each is read as you go", systemImage: "camera")
                    }
                    .disabled(isCameraDenied)
                } footer: {
                    if isCameraDenied {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Camera access is off for Kitchen Codex. Turn it on in Settings to scan with the camera.")
                            Button("Open Settings") { CameraAccess.openSettings() }
                        }
                    }
                }
            }
            Section {
                Button {
                    isChoosingPhotos = true
                } label: {
                    choiceLabel("From Photo", detail: "One or more pages from Photos, in the order you choose them", systemImage: "photo.on.rectangle")
                }
                Button {
                    isChoosingFiles = true
                } label: {
                    choiceLabel("Files", detail: "Photos of pages saved as image files", systemImage: "folder")
                }
            } footer: {
                Text("A cookbook page or a recipe card. A recipe that runs over a page turn: choose both pages, in order. A photo of the book's barcode among them names the book.")
            }
        }
    }

    private func choiceLabel(_ title: String, detail: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .padding(.vertical, 4)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if session.phase != .finished {
                Button(role: .cancel) {
                    if session.phase == .reviewing, session.review?.hasChanges == true {
                        isConfirmingCancel = true
                    } else {
                        finish(session.saved.map(\.recipe))
                    }
                }
                // Escape cancels the sheet (03 §4, ux-notes row 43).
                .keyboardShortcut(.cancelAction)
                .confirmationDialog("Discard this review?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { finish(session.saved.map(\.recipe)) }
                    Button("Keep Reviewing", role: .cancel) {}
                } message: {
                    Text("This page isn't saved. Recipes already saved from the scan stay.")
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch session.phase {
            case .reviewing:
                Button("Save", role: .confirm) {
                    Task { await session.saveReview() }
                }
                .disabled(!canSave)
            case .finished:
                Button("Done", role: .confirm) { finish([]) }
            default:
                EmptyView()
            }
        }
    }

    /// Every recipe kept has a title, and at least one is kept.
    private var canSave: Bool {
        guard let review = session.review, !session.isSaving else { return false }
        let kept = review.recipes.filter { !$0.isSkipped }
        return !kept.isEmpty && kept.allSatisfy { $0.title?.text.trimmed.isEmpty == false }
    }

    private func finish(_ recipes: [Recipe]) {
        onFinish(recipes)
        dismiss()
    }
}

/// Flow B step 4's processing sheet: each photo's stages as the pipeline reports them ("Reading
/// text… Finding ingredients… Finding steps…"), the quality gate's reading as a line that never
/// stops anything, and the model's own line when it is asked.
private struct ScanProcessingView: View {
    let session: ScanSession

    var body: some View {
        List {
            ForEach(session.progress) { page in
                Section(session.progress.count > 1 ? "Photo \(page.id + 1) of \(session.progress.count)" : "") {
                    if let isbn = page.isbn {
                        Label("The book's barcode: ISBN \(isbn)", systemImage: "barcode")
                            .foregroundStyle(.secondary)
                    } else if page.isPhoto {
                        stage("A photo for a recipe…", done: page.step == .done, started: page.step >= .checking, result: page.step == .done ? "With its recipe" : nil)
                    } else {
                        stage("Checking the photo…", done: page.step > .checking, started: page.step >= .checking, result: page.quality.map(qualityLine))
                        stage("Reading text…", done: page.step > .reading, started: page.step >= .reading, result: page.lines.map { $0 == 1 ? "1 line" : "\($0) lines" })
                        if page.kind == nil || page.kind == .recipe {
                            stage("Finding ingredients…", done: page.step == .done, started: page.step >= .structuring, result: page.step == .done ? count(page.ingredients, "ingredient") : nil)
                            stage("Finding steps…", done: page.step == .done, started: page.step >= .structuring, result: page.step == .done ? count(page.steps, "step") + (page.recipes > 1 ? " · \(page.recipes) recipes" : "") : nil)
                        } else if let kind = page.kind {
                            Label("Not a recipe: \(kind.title.lowercased())", systemImage: "doc.text.magnifyingglass")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let refining = session.refining {
                Section {
                    // HIG Generative AI: say specifically what the model is doing.
                    Label {
                        Text("Apple Intelligence is reading \(refining)…")
                    } icon: {
                        ProgressView()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.default, value: session.progress)
    }

    private func count(_ value: Int, _ noun: String) -> String {
        value == 1 ? "1 \(noun)" : "\(value) \(noun)s"
    }

    private func qualityLine(_ reading: PageQualityReading) -> String {
        switch reading.quality {
        case .sharp: "Sharp"
        case .holdStill: "Hold still: the photo is soft"
        case .cleanTheLens: "Clean the lens: the photo looks hazy"
        }
    }

    private func stage(_ title: String, done: Bool, started: Bool, result: String?) -> some View {
        HStack {
            Label {
                Text(title)
                    .foregroundStyle(started ? .primary : .tertiary)
            } icon: {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if started {
                    ProgressView()
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let result {
                Text(result)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension PageKind {
    /// What a page that is not a recipe is, as the scan says it.
    var title: String {
        switch self {
        case .recipe: "A recipe"
        case .contents: "A contents page"
        case .index: "An index page"
        case .sources: "A Sources page"
        case .photo: "A photo plate"
        case .prose: "Running prose"
        case .blank: "A blank page"
        case .unreadable: "Too little text to read"
        }
    }

    var systemImage: String {
        switch self {
        case .recipe: "fork.knife"
        case .contents, .index: "list.number"
        case .sources: "storefront"
        case .photo: "photo"
        case .prose: "text.alignleft"
        case .blank, .unreadable: "doc"
        }
    }
}

/// Which book? (04 §5.1 "Which book"): a page scanned on its own belongs to a book on the shelf,
/// recent first, a new one found by its barcode photo, or none (a recipe card, a clipping).
private struct WhichBookView: View {
    let session: ScanSession

    @Query private var books: [Book]
    @State private var isAddingBook = false
    @State private var addedBook: Book?

    /// The shelf, the book most recently added to or scanned from first.
    private var recentBooks: [Book] {
        books.sorted { lastUsed($0) > lastUsed($1) }
    }

    private func lastUsed(_ book: Book) -> Date {
        ((book.recipes ?? []).map(\.createdAt) + [book.addedAt]).max() ?? book.addedAt
    }

    var body: some View {
        List {
            Section {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !books.isEmpty {
                Section("On Your Shelf") {
                    ForEach(recentBooks) { book in
                        Button {
                            session.choose(book)
                        } label: {
                            HStack(spacing: 12) {
                                Color.clear
                                    .frame(width: 36, height: 54)
                                    .overlay { BookCoverImage(book: book, pointSize: 60) }
                                    .clipShape(.rect(cornerRadius: 3))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(book.displayTitle).foregroundStyle(.primary)
                                    if !book.author.isEmpty {
                                        Text(book.author)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Button("New Cookbook from Barcode", systemImage: "barcode.viewfinder") { isAddingBook = true }
            } footer: {
                Text(ISBNScanner.isSupported ? "Scan the barcode on the back cover, or choose a photo of it, to add the book to your shelf." : "A photo of the barcode on the back cover adds the book to your shelf.")
            }
            Section {
                Button("No Book", systemImage: "rectangle.portrait.on.rectangle.portrait.slash") { session.choose(nil) }
            } footer: {
                Text("A recipe card, a clipping or a magazine page.")
            }
        }
        .sheet(isPresented: $isAddingBook, onDismiss: {
            if let addedBook { session.choose(addedBook) }
        }) {
            AddCookbookView { book in addedBook = book }
        }
        // A barcode among the pages for a book not on the shelf: its card (ux-notes row 65). Cancel
        // leaves Which book? to answer.
        .sheet(item: Binding { session.newBookISBN.map(PendingISBN.init) } set: { if $0 == nil { session.newBookISBN = nil } }, onDismiss: {
            if let addedBook { session.addedBook(addedBook) }
        }) { pending in
            AddCookbookView(isbn: pending.id) { book in addedBook = book }
        }
    }

    private struct PendingISBN: Identifiable {
        let id: String
    }

    /// What was read, so the cook knows which book to pick: "“Roast Chicken” and 1 more · p. 12".
    private var summary: String {
        let recipes = session.readings.flatMap(\.recipes).map(\.title).filter { !$0.isEmpty }
        let pages = session.readings.compactMap(\.pageNumber)
        var parts: [String] = []
        if let first = recipes.first {
            parts.append(recipes.count > 1 ? "“\(first)” and \(recipes.count - 1) more" : "“\(first)”")
        } else if let kind = session.readings.first?.kind, kind != .recipe {
            parts.append(kind.title)
        }
        if let page = pages.first { parts.append("p. \(page)") }
        let read = parts.isEmpty ? "" : parts.joined(separator: " · ") + ". "
        return read + "Which book is it from?"
    }
}

/// A photo that is not a recipe says what it is, and keeps it on a book as a page scan (a contents
/// page for the punchlist, a Sources page, a photo plate) or lets it go.
private struct NotARecipeView: View {
    let session: ScanSession

    @Query(sort: [SortDescriptor(\Book.title, comparator: .localizedStandard)]) private var books: [Book]
    @State private var image: UIImage?

    var body: some View {
        let kind = session.reading?.kind ?? .unreadable
        ScrollView {
            VStack(spacing: 20) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .clipShape(.rect(cornerRadius: 8))
                        .accessibilityHidden(true)
                }
                ContentUnavailableView {
                    Label(kind.title, systemImage: kind.systemImage)
                } description: {
                    Text("This photo isn't a recipe. Keep it with its book as a page scan, or discard it.")
                }
                VStack(spacing: 12) {
                    if let book = session.book {
                        Button("Keep as Page Scan in \(book.displayTitle)") {
                            Task { await session.keepPage(on: book) }
                        }
                        .buttonStyle(.borderedProminent)
                    } else if !books.isEmpty {
                        Menu("Keep as Page Scan…") {
                            ForEach(books) { book in
                                Button(book.displayTitle) { Task { await session.keepPage(on: book) } }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Discard", role: .destructive) {
                        Task { await session.keepPage(on: nil) }
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(session.isSaving)
            }
            .padding()
        }
        .task(id: session.position) {
            guard let page = session.review?.pages.first else { return }
            image = await ScanImage.upright(page, maxPixelSize: 1_200).map(UIImage.init(cgImage:))
        }
    }
}

/// The scan's end when it saved more than one recipe: each with how it was saved, a tap opening it.
private struct ScanSummaryView: View {
    let session: ScanSession
    var onOpen: (Recipe) -> Void

    var body: some View {
        List {
            if let book = session.barcodeBook {
                Section {
                    Label("\(book.displayTitle), named by its barcode", systemImage: "barcode")
                }
            }
            if !session.saved.isEmpty {
                Section(session.saved.count == 1 ? "1 Recipe Saved" : "\(session.saved.count) Recipes Saved") {
                    ForEach(session.saved) { saved in
                        Button {
                            onOpen(saved.recipe)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.recipe.title).foregroundStyle(.primary)
                                Text(saved.reviewed ? "Reviewed" : (saved.recipe.needsReview ? "Accepted automatically · needs a look" : "Accepted automatically"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if session.keptPages + session.discardedPages > 0 {
                Section {
                    if session.keptPages > 0 {
                        Label(session.keptPages == 1 ? "1 page kept as a page scan" : "\(session.keptPages) pages kept as page scans", systemImage: "doc.text.image")
                    }
                    if session.discardedPages > 0 {
                        Label(session.discardedPages == 1 ? "1 page discarded" : "\(session.discardedPages) pages discarded", systemImage: "trash")
                    }
                }
            }
            if session.saved.isEmpty, session.keptPages == 0 {
                Section {
                    Text("Nothing was saved.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
