import RecipeModel
import SwiftData
import SwiftUI

/// A cookbook (03 §3.7), pushed over the shelf: cover, title, author, year and ISBN; the
/// completeness ring and "47 of 112 captured, 3 need review" once there is a punchlist, the review
/// queue a tap away; **Continue Scanning**, or, while there is no list, Build the Recipe List with
/// a plain Scan Recipes Instead under it (ux-notes row 114); Sections · Index · Missing over the
/// punchlist, a listed entry offering Scan Now at its page. A list of chapters with no recipes is
/// a list (row 117): the chapters show with "Recipes are added as you scan". The Index tab lists
/// the book's index pages when it has them. An entry captured as reference reading shows under
/// Reading only, with the book's chapters and techniques beside its recipes (row 122, 04 §5.1
/// "References home"). More holds Edit Book Info, Edit Recipe List, Scan Sources Page (02 Flow C
/// step 8) and Delete Cookbook; Export List arrives with its slice.
struct BookDetailView: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    enum Punchlist: String, CaseIterable, Identifiable {
        case sections = "Sections"
        case index = "Index"
        case missing = "Missing"
        var id: Self { self }
    }

    @State private var punchlist = Punchlist.sections
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var showsNavigationTitle = false
    /// The whole-book session, opened at an entry by Scan Now.
    @State private var scanning: ScanStart?
    @State private var isBuildingList = false
    @State private var isEditingList = false
    /// Edit beside the switcher on the Index tab: the index's entries by hand (ux-notes row 152).
    @State private var isEditingIndex = false
    @State private var isReviewing = false
    /// More → Scan Sources Page: the one-off scan, expecting the Sources page.
    @State private var isScanningSources = false

    struct ScanStart: Identifiable {
        let id = UUID()
        var entry: BookEntry?
        /// Recipe pages offered as contents pages: the session's first captures.
        var pages: [URL] = []
        /// Rescan: the recipe the next capture replaces (ux-notes row 164).
        var rescanning: UUID?
    }

    var body: some View {
        let progress = book.punchlistProgress
        let reviewCount = book.reviewCount
        // A list of chapters with no recipes yet is a list (ux-notes row 117).
        let hasList = !book.orderedSections.isEmpty
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            // The ring waits until a contents or index page has been captured (ux-notes rows 52,
            // 165); the review row shows whenever something waits for a look.
            if progress != nil || reviewCount > 0 {
                Section {
                    if let progress {
                        CompletenessRow(progress: progress)
                    }
                    if reviewCount > 0 {
                        Button(reviewCount == 1 ? "Review 1 Recipe" : "Review \(reviewCount) Recipes", systemImage: "rectangle.and.text.magnifyingglass") {
                            isReviewing = true
                        }
                    }
                }
            }

            // The primary action (03 §3.7): Continue Scanning once there is a list; while there is
            // none, Build the Recipe List, and Scan Recipes Instead for a list that grows as pages
            // are scanned (ux-notes row 114).
            Section {
                if hasList {
                    // The title alone, centred, as Build the Recipe List is (ux-notes rows 115, 153).
                    Button {
                        scanning = ScanStart()
                    } label: {
                        Text((book.recipes ?? []).isEmpty && (progress?.captured ?? 0) == 0 ? "Start Scanning" : "Continue Scanning")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    // The title alone, centred (ux-notes row 115).
                    Button {
                        isBuildingList = true
                    } label: {
                        Text("Build the Recipe List")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    Button("Scan Recipes Instead") { scanning = ScanStart() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderless)
                        .listRowBackground(Color.clear)
                }
            } footer: {
                if !hasList {
                    Text("Photograph or choose the contents pages; their recipes and pages become the list you scan from.")
                }
            }

            Section {
                // Edit beside the switcher opens the editor for the tab shown (ux-notes row 152):
                // the sections and their recipes, or the index's entries, with the page each was
                // read from.
                HStack(spacing: 12) {
                    Picker("Punchlist", selection: $punchlist) {
                        ForEach(Punchlist.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if hasList || !book.indexEntries.isEmpty {
                        Button("Edit") {
                            if punchlist == .index { isEditingIndex = true } else { isEditingList = true }
                        }
                        .accessibilityHint(punchlist == .index ? "Edits the index's entries." : "Edits the sections and recipes.")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            punchlistContent(hasList: hasList)

            let reading = (book.references ?? []).sorted { ($0.source?.firstPage ?? $0.bookEntry?.page ?? .max, $0.title) < ($1.source?.firstPage ?? $1.bookEntry?.page ?? .max, $1.title) }
            if !reading.isEmpty {
                Section("Reading") {
                    ForEach(reading) { reference in
                        NavigationLink(value: LibraryRoute.reference(reference.persistentModelID)) {
                            HStack(spacing: 10) {
                                Image(systemName: "text.book.closed")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text(reference.title.isEmpty ? "Reference" : reference.title)
                                Spacer(minLength: 8)
                                Text(referencePages(reference))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 140
        } action: { _, isPast in
            showsNavigationTitle = isPast
        }
        .navigationTitle(showsNavigationTitle ? book.displayTitle : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Book Info", systemImage: "pencil") { isEditing = true }
                    if !book.orderedSections.isEmpty {
                        Button("Edit Recipe List", systemImage: "list.bullet.rectangle") { isEditingList = true }
                    }
                    Button(book.orderedSections.isEmpty ? "Build the Recipe List" : "Read More Contents Pages", systemImage: "list.number") { isBuildingList = true }
                    Button("Scan Sources Page", systemImage: "storefront") { isScanningSources = true }
                    Divider()
                    Button("Delete Cookbook", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                // On the menu, so on iPad the confirmation points at More.
                .confirmationDialog("Delete “\(book.displayTitle)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete Cookbook", role: .destructive) {
                        isDeleting = true
                        dismiss()
                    }
                } message: {
                    Text("Its recipes stay in your library.")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            BookInfoEditor(book: book)
        }
        .sheet(isPresented: $isBuildingList) {
            NavigationStack {
                BuildRecipeListView(book: book) {
                    isBuildingList = false
                    isEditingList = true
                } onScanRecipes: { pages in
                    // The session once the sheet has gone, the pages its first captures.
                    isBuildingList = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        scanning = ScanStart(pages: pages)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { isBuildingList = false }
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
        }
        .sheet(isPresented: $isEditingList) {
            NavigationStack {
                PunchlistEditorView(book: book) { isEditingList = false }
            }
        }
        .sheet(isPresented: $isEditingIndex) {
            NavigationStack {
                IndexEditorView(book: book) { isEditingIndex = false }
            }
        }
        .reviewPresentation(isPresented: $isReviewing) {
            // Rescan: the book session's camera at the recipe's entry, once the queue has gone, the
            // recipe named so the next capture replaces it (ux-notes row 164).
            BookReviewQueueView(book: book) { entry, recipe in
                isReviewing = false
                let id = recipe.id
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    scanning = ScanStart(entry: entry, rescanning: id)
                }
            }
        }
        .reviewPresentation(isPresented: $isScanningSources) {
            ScanPageView(book: book, expectsSources: true) { _ in }
        }
        .fullScreenCover(item: $scanning) { start in
            BookScanView(book: book, startAt: start.entry, firstPages: start.pages, rescanning: start.rescanning)
        }
        .onAppear {
            book.reconcilePunchlist()
            BookScanStore.shared.updateState(for: book) { CrossReferenceLinking.prune(in: book, state: &$0, context: modelContext) }
        }
        .onDisappear {
            // Delete after the pop so the view never renders a deleted model. The book's recipes
            // stay, their link to it cleared (`Book.recipes` nullifies).
            guard isDeleting else { return }
            // Its whole-book session, with any captures still waiting, goes with it.
            BookScanStore.shared.forget(bookID: book.id)
            modelContext.delete(book)
            try? modelContext.save()
        }
    }

    /// The session at the entry; an index line first lists its recipe in the chapter its page falls
    /// in, as a page pointer's Scan Page N does.
    private func scanNow(_ entry: BookEntry) {
        if entry.section?.isIndex == true, let page = entry.page {
            scanning = ScanStart(entry: book.toScanEntry(page: page, title: entry.title, in: modelContext).entry)
        } else {
            scanning = ScanStart(entry: entry)
        }
    }

    /// "p. 250", "pp. 250–253".
    private func referencePages(_ reference: Reference) -> String {
        if let first = reference.source?.firstPage, let last = reference.source?.lastPage, last != first { return "pp. \(first)–\(last)" }
        if let page = reference.source?.firstPage ?? reference.bookEntry?.page { return "p. \(page)" }
        return ""
    }

    /// Cover beside the title, author, year and ISBN: the cover whole at a fixed height with its
    /// own width (ux-notes row 150).
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            BookCoverImage(book: book, pointSize: 180)
                .frame(height: 168)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.displayTitle)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let year = book.publicationYear {
                        Text(String(year))
                    }
                    if let isbn = book.isbn {
                        Text("ISBN \(isbn)")
                            .textSelection(.enabled)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func punchlistContent(hasList: Bool) -> some View {
        // Chapters with no recipes listed (ux-notes row 117): each scanned recipe files in the
        // chapter its page falls in.
        let total = book.entries.count
        if !hasList, book.indexEntries.isEmpty {
            Section {
                Text("No recipes listed yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        } else {
            switch punchlist {
            case .sections:
                let sections = book.orderedSections
                if total == 0 {
                    Section {
                        ForEach(sections) { section in
                            HStack {
                                Text(section.displayTitle)
                                Spacer(minLength: 8)
                                if let page = section.startPage {
                                    Text("p. \(page)")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } footer: {
                        Text("Recipes are added as you scan.")
                    }
                } else {
                    let pointerMade = Set(BookScanStore.shared.state(for: book)?.pointerEntries.filter(\.madeEntry).map(\.entry) ?? [])
                    ForEach(sections) { section in
                        // An entry captured as reference reading shows under Reading only (row 122).
                        let entries = section.orderedEntries.filter { !$0.isReading(in: book) }
                        // Entries page pointers made count only in Missing (ux-notes row 165).
                        let counted = entries.filter { !pointerMade.contains($0.id) }
                        Section {
                            ForEach(entries) { EntryRow(entry: $0) { scanNow($0) } }
                        } header: {
                            HStack {
                                Text(section.title.isEmpty ? "Untitled Section" : section.title)
                                Spacer()
                                // No count on a chapter with nothing listed (ux-notes row 147).
                                if !counted.isEmpty {
                                    Text("\(counted.count { $0.status != .listed }) of \(counted.count)")
                                }
                            }
                        }
                    }
                    if sections.contains(where: { $0.orderedEntries.isEmpty }) {
                        Section {} footer: {
                            Text("Recipes are added as you scan.")
                        }
                    }
                }
            case .index:
                Section {
                    // The book's index pages, when it has them (ux-notes row 117), else the list.
                    let index = book.indexEntries
                    let rows = (index.isEmpty ? book.entries : index).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                    ForEach(rows) { entry in
                        if entry.section?.isIndex == true {
                            IndexEntryRow(entry: entry, book: book) { scanNow($0) }
                        } else {
                            EntryRow(entry: entry) { scanNow($0) }
                        }
                    }
                }
            case .missing:
                // By page, entries on one page in the list's order.
                let missing = book.orderedEntries.filter { $0.status == .listed }.sorted { ($0.page ?? .max) < ($1.page ?? .max) }
                Section {
                    if total == 0 {
                        Text("Recipes are added as you scan")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    } else if missing.isEmpty {
                        Text("Every listed recipe is captured")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(missing) { entry in
                            EntryRow(entry: entry, showsScanNow: true) { scanning = ScanStart(entry: $0) }
                        }
                    }
                }
            }
        }
    }
}

extension BookEntry {
    /// Captured as reference reading (a glossary, a chapter opener): the book's Reading lists it,
    /// with its pages.
    func isReading(in book: Book) -> Bool {
        guard status != .listed, recipe == nil else { return false }
        if reference != nil { return true }
        return page.map { !book.references(onPage: $0).isEmpty } ?? false
    }
}

/// One line of the book's index (ux-notes row 117): what the book holds from its page opens; with
/// nothing there, Scan Now lists the recipe in its chapter and opens the session at it.
private struct IndexEntryRow: View {
    let entry: BookEntry
    let book: Book
    var onScan: (BookEntry) -> Void

    @State private var isOffering = false

    var body: some View {
        switch entry.page.map({ book.holding(pages: [$0], named: entry.title, from: nil) }) {
        case let .recipe(recipe):
            NavigationLink(value: LibraryRoute.recipe(recipe.persistentModelID)) {
                line(PunchlistMark(state: recipe.needsReview ? .needsReview : .captured))
            }
        case let .reference(reference):
            NavigationLink(value: LibraryRoute.reference(reference.persistentModelID)) {
                line(PunchlistMark(state: .captured))
            }
        default:
            // The dialog on the row, so its arrow points at the row (ux-notes row 167).
            Button { isOffering = true } label: { line(PunchlistMark(state: .listed)) }
                .buttonStyle(.plain)
                .accessibilityHint("Offers to scan it now.")
                .scanNowDialog(for: entry, isPresented: $isOffering) { onScan(entry) }
        }
    }

    private func line(_ mark: PunchlistMark) -> some View {
        HStack(spacing: 10) {
            mark
            Text(entry.displayTitle)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if let page = entry.page {
                Text("p. \(page)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The completeness ring and its line: "47 of 112 captured, 3 need review", or "about 12 of 320
/// pages captured" while the list has chapters but no recipes (ux-notes row 165). Shown once a
/// contents or index page has been captured.
private struct CompletenessRow: View {
    let progress: PunchlistProgress

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.fill.secondary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress.total == 0 ? 0 : CGFloat(progress.captured) / CGFloat(progress.total))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
            Text(progress.line)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Scan Now, presented from the row tapped so its arrow points at the row (ux-notes row 167).
    func scanNowDialog(for entry: BookEntry, isPresented: Binding<Bool>, action: @escaping () -> Void) -> some View {
        confirmationDialog("“\(entry.displayTitle)”", isPresented: isPresented, titleVisibility: .visible) {
            Button(entry.page.map { "Scan Now, p. \($0)" } ?? "Scan Now", action: action)
        } message: {
            Text("Not captured yet.")
        }
    }
}

/// One punchlist entry: its title, page and status. A captured entry opens its recipe; a listed one
/// offers Scan Now at its page (03 §3.7), at once in the Missing list.
private struct EntryRow: View {
    let entry: BookEntry
    var showsScanNow = false
    var onScan: (BookEntry) -> Void

    @State private var isOffering = false

    var body: some View {
        if let recipe = entry.recipe {
            NavigationLink(value: LibraryRoute.recipe(recipe.persistentModelID)) { PunchlistEntryLine(entry: entry) }
        } else if let reference = entry.reference ?? entry.page.flatMap({ page in entry.section?.book?.references(onPage: page).first }) {
            // Reference reading captured from the entry's page opens it.
            NavigationLink(value: LibraryRoute.reference(reference.persistentModelID)) { PunchlistEntryLine(entry: entry) }
        } else if entry.status != .listed {
            // Captured with nothing to open here: the book's Sources page, whose suppliers are in
            // Pantry → Sources.
            PunchlistEntryLine(entry: entry)
                .accessibilityHint("Captured; its suppliers are in Pantry, Sources.")
        } else if showsScanNow {
            HStack {
                PunchlistEntryLine(entry: entry)
                Button("Scan Now") { onScan(entry) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Scan \(entry.displayTitle) now")
            }
        } else {
            Button { isOffering = true } label: { PunchlistEntryLine(entry: entry) }
                .buttonStyle(.plain)
                .accessibilityHint("Offers to scan it now.")
                .scanNowDialog(for: entry, isPresented: $isOffering) { onScan(entry) }
        }
    }
}
