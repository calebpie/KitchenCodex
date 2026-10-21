import RecipeModel
import SwiftData
import SwiftUI

/// A Reference, read-only (02 §4.2, 03 §3.17 References): where it came from, its sections (a
/// glossary's entries, each headed by its term) and the recipes it informs. Pushed from the
/// References pane, a book's detail and Search; a sheet from a pointer's pill or a recipe's Related
/// reading, opened at the entry the pointer named. More holds Edit and Delete.
struct ReferencePageView: View {
    let reference: Reference
    /// The term a pointer named ("yama-imo"): its entry is scrolled to and marked.
    var term: String?
    /// Opening one of its recipes: from a sheet, the sheet closes first.
    var onOpenRecipe: ((Recipe) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var isViewingPages = false

    private var highlighted: ReferenceSection? { reference.section(matching: term) }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                ForEach(reference.sortedSections) { section in
                    Section {
                        Text(section.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        if !section.heading.isEmpty {
                            Text(section.heading)
                                .foregroundStyle(section == highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .fontWeight(section == highlighted ? .semibold : .regular)
                        }
                    }
                    .id(section.id)
                }
                let recipes = reference.sortedRecipes
                if !recipes.isEmpty {
                    Section("Informs") {
                        ForEach(recipes) { recipe in
                            Button {
                                onOpenRecipe?(recipe)
                            } label: {
                                RecipeRow(recipe: recipe)
                            }
                            .buttonStyle(.plain)
                            .disabled(onOpenRecipe == nil)
                            .accessibilityHint("Opens the recipe.")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onAppear {
                if let highlighted { proxy.scrollTo(highlighted.id, anchor: .top) }
            }
        }
        .navigationTitle(reference.title.isEmpty ? "Reference" : reference.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    if !reference.pageScans.isEmpty {
                        Button("View Page", systemImage: "doc.text.image") { isViewingPages = true }
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .confirmationDialog("Delete “\(reference.title)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete Reference", role: .destructive) {
                        isDeleting = true
                        dismiss()
                    }
                } message: {
                    Text("Its recipes stay in your library; they just stop pointing here.")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ReferenceEditor(reference: reference)
        }
        .fullScreenCover(isPresented: $isViewingPages) {
            ReferencePagesViewer(reference: reference)
        }
        .onDisappear {
            // Delete after the pop so the view never renders a deleted model.
            guard isDeleting else { return }
            ReferenceSaving.delete(reference, in: modelContext)
        }
    }

    /// Title, source, kind and size, and View Page for a scanned one.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reference.title.isEmpty ? "Reference" : reference.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let url = reference.source?.url {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(reference.sourceLine)
                        Image(systemName: "arrow.up.right")
                            .imageScale(.small)
                    }
                }
                .font(.subheadline)
                .accessibilityHint("Opens the article's web page.")
            } else {
                Text(reference.sourceLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(kindLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !reference.pageScans.isEmpty {
                    Button("View Page", systemImage: "doc.text.image") { isViewingPages = true }
                        .font(.subheadline)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// "Chapter · 12 entries", "Article · 4 sections", "Technique · Reviewed Oct 21".
    private var kindLine: String {
        let count = reference.sortedSections.count
        let sections = reference.sortedSections.allSatisfy { !$0.heading.isEmpty } && count > 1
            ? (count == 1 ? "1 entry" : "\(count) entries")
            : (count == 1 ? "1 section" : "\(count) sections")
        var parts = [reference.kind.word, sections]
        if reference.book != nil {
            parts.append(reference.source?.reviewedAt.map { "Reviewed \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Accepted automatically")
        }
        return parts.joined(separator: " · ")
    }
}

/// The page as a sheet, from a pill or Related reading: Done closes it, and a recipe row closes it
/// and opens the recipe in Recipes.
struct ReferenceSheet: View {
    let reference: Reference
    var term: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ReferencePageView(reference: reference, term: term) { recipe in
                dismiss()
                router.openRecipe(id: recipe.id)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}

// MARK: - Editing

/// What the editor and the review queue change: the title, kind and author, and the sections.
struct ReferenceDraft: Equatable {
    struct SectionDraft: Identifiable, Equatable {
        let id: UUID
        var heading: String
        var body: String

        init(id: UUID = UUID(), heading: String = "", body: String = "") {
            self.id = id
            self.heading = heading
            self.body = body
        }
    }

    var title = ""
    var kind = ReferenceKind.chapter
    var author = ""
    var sections: [SectionDraft] = []

    init() {}

    init(reference: Reference) {
        title = reference.title
        kind = reference.kind
        author = reference.author
        sections = reference.sortedSections.map { SectionDraft(id: $0.id, heading: $0.heading, body: $0.body) }
    }

    var canSave: Bool { !title.trimmed.isEmpty }

    /// Writes the draft back: sections matched by id, new ones added, missing ones deleted.
    func apply(to reference: Reference, in context: ModelContext) {
        reference.title = title.trimmed
        reference.kind = kind
        reference.author = author.trimmed
        let existing = Dictionary(reference.sortedSections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = Set(sections.map(\.id))
        for section in reference.sortedSections where !kept.contains(section.id) {
            context.delete(section)
        }
        for (index, draft) in sections.enumerated() {
            let section = existing[draft.id] ?? {
                let made = ReferenceSection()
                context.insert(made)
                made.reference = reference
                return made
            }()
            section.heading = draft.heading.trimmed
            section.body = draft.body.trimmed
            section.sortOrder = index
        }
        try? context.save()
    }
}

/// The title, kind, author and sections as fields; shared by Edit and the review queue.
struct ReferenceForm: View {
    @Binding var draft: ReferenceDraft

    var body: some View {
        Section {
            TextField("Title", text: $draft.title, axis: .vertical)
                .font(.headline)
            Picker("Kind", selection: $draft.kind) {
                ForEach(ReferenceKind.allCases, id: \.self) { Text($0.word).tag($0) }
            }
            TextField("Author", text: $draft.author)
        }
        ForEach($draft.sections) { $section in
            Section {
                TextField("Heading", text: $section.heading)
                    .font(.headline)
                TextField("Text", text: $section.body, axis: .vertical)
                    .lineLimit(3...12)
            }
        }
        .onDelete { offsets in draft.sections.remove(atOffsets: offsets) }
        .onMove { from, to in draft.sections.move(fromOffsets: from, toOffset: to) }
        Section {
            Button("Add Section", systemImage: "plus") { draft.sections.append(.init()) }
        }
    }
}

/// More → Edit: the reference's fields, saved on Done.
struct ReferenceEditor: View {
    let reference: Reference

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft = ReferenceDraft()

    var body: some View {
        NavigationStack {
            Form {
                ReferenceForm(draft: $draft)
            }
            .navigationTitle("Edit Reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        draft.apply(to: reference, in: modelContext)
                        dismiss()
                    }
                    .disabled(!draft.canSave)
                }
            }
            .onAppear { draft = ReferenceDraft(reference: reference) }
        }
    }
}

/// The review queue's page for a reference (02 Flow C step 7): the page scan beside (iPad) or over
/// (iPhone) its title, kind and sections, which Save keeps and marks reviewed.
struct ReferenceReviewView: View {
    let reference: Reference
    @Binding var draft: ReferenceDraft

    @State private var image: UIImage?
    @State private var width: CGFloat = 0

    var body: some View {
        Group {
            if width >= 700 {
                HStack(spacing: 0) {
                    page
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    Form { ReferenceForm(draft: $draft) }
                        .frame(width: min(440, width * 0.42))
                }
            } else {
                Form {
                    Section {
                        page
                            .frame(height: 260)
                            .listRowInsets(EdgeInsets())
                    }
                    ReferenceForm(draft: $draft)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: reference.id) {
            guard let data = reference.pageScans.first?.imageData else { return }
            image = await ImageProcessing.thumbnail(from: data, maxPixelSize: 1_600)
        }
    }

    @ViewBuilder
    private var page: some View {
        if let image {
            ZoomablePage(aspectRatio: image.size.width / max(1, image.size.height), focus: nil) {
                Image(uiImage: image)
                    .resizable()
                    .accessibilityLabel("The page")
            }
            .background(.background.secondary)
        } else {
            ContentUnavailableView("No Page Scan", systemImage: "doc.viewfinder")
        }
    }
}

/// View Page for a reference: its page scans, zoomable, several pages swiping.
struct ReferencePagesViewer: View {
    let reference: Reference

    @Environment(\.dismiss) private var dismiss
    @State private var images: [UUID: UIImage] = [:]
    @State private var page: UUID?

    var body: some View {
        NavigationStack {
            let scans = reference.pageScans
            TabView(selection: $page) {
                ForEach(scans) { scan in
                    Group {
                        if let image = images[scan.id] {
                            ZoomablePage(aspectRatio: image.size.width / max(1, image.size.height), focus: nil) {
                                Image(uiImage: image)
                                    .resizable()
                                    .accessibilityLabel(scan.pageNumber.map { "Page \($0)" } ?? "The page")
                            }
                        } else {
                            ProgressView()
                        }
                    }
                    .tag(Optional(scan.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: scans.count > 1 ? .always : .never))
            .background(.background.secondary)
            .navigationTitle(title(for: scans))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .task {
            for scan in reference.pageScans {
                guard let data = scan.imageData else { continue }
                images[scan.id] = await ImageProcessing.thumbnail(from: data, maxPixelSize: 3_000)
            }
        }
    }

    private func title(for scans: [RecipeImage]) -> String {
        let shown = scans.first { $0.id == page } ?? scans.first
        return shown?.pageNumber.map { "Page \($0)" } ?? reference.title
    }
}
