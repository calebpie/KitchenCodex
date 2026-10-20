import RecipeModel
import SwiftData
import SwiftUI

/// A cookbook (03 §3.7), pushed over the shelf: cover, title, author, year and ISBN; the
/// completeness ring; Sections · Index · Missing over the punchlist, which stays empty until the
/// contents pages are read (Phase 2 slice 5). More holds Edit Book Info and Delete Cookbook;
/// Continue Scanning, Export List and Scan Sources Page arrive with their slices.
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

    var body: some View {
        let progress = book.punchlistProgress
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section {
                CompletenessRow(captured: progress.captured, total: progress.total, needReview: progress.needReview)
            }

            Section {
                Picker("Punchlist", selection: $punchlist) {
                    ForEach(Punchlist.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            punchlistContent(total: progress.total)
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
        .onDisappear {
            // Delete after the pop so the view never renders a deleted model. The book's recipes
            // stay, their link to it cleared (`Book.recipes` nullifies).
            guard isDeleting else { return }
            modelContext.delete(book)
            try? modelContext.save()
        }
    }

    /// Cover beside the title, author, year and ISBN.
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Color.clear
                .frame(width: 112, height: 168)
                .overlay { BookCoverImage(book: book, pointSize: 180) }
                .clipShape(.rect(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5) }
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
    private func punchlistContent(total: Int) -> some View {
        if total == 0 {
            Section {
                Text("No recipes listed yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        } else {
            switch punchlist {
            case .sections:
                ForEach((book.sections ?? []).sorted { $0.sortOrder < $1.sortOrder }) { section in
                    let entries = (section.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
                    Section {
                        ForEach(entries) { EntryRow(entry: $0) }
                    } header: {
                        HStack {
                            Text(section.title.isEmpty ? "Untitled Section" : section.title)
                            Spacer()
                            Text("\(entries.count { $0.status != .listed }) of \(entries.count)")
                        }
                    }
                }
            case .index:
                Section {
                    ForEach(book.entries.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { EntryRow(entry: $0) }
                }
            case .missing:
                let missing = book.entries.filter { $0.status == .listed }.sorted { ($0.page ?? .max) < ($1.page ?? .max) }
                Section {
                    if missing.isEmpty {
                        Text("Every listed recipe is captured")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(missing) { EntryRow(entry: $0) }
                    }
                }
            }
        }
    }
}

/// The completeness ring and its line: "47 of 112 captured, 3 need review", or "No recipes listed
/// yet" before the punchlist exists.
private struct CompletenessRow: View {
    let captured: Int
    let total: Int
    let needReview: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.fill.secondary, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: total == 0 ? 0 : CGFloat(captured) / CGFloat(total))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
            Text(line)
                .foregroundStyle(total == 0 ? .secondary : .primary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        guard total > 0 else { return "No recipes listed yet" }
        let base = "\(captured) of \(total) captured"
        return needReview > 0 ? "\(base), \(needReview) need review" : base
    }
}

/// One punchlist entry: its title, page and whether it is captured. A captured entry opens its recipe.
private struct EntryRow: View {
    let entry: BookEntry

    var body: some View {
        if let recipe = entry.recipe {
            NavigationLink(value: LibraryRoute.recipe(recipe.persistentModelID)) { label }
        } else {
            label
        }
    }

    private var label: some View {
        HStack {
            Image(systemName: entry.status == .listed ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(entry.status == .listed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .accessibilityLabel(entry.status == .listed ? "Not captured" : "Captured")
            Text(entry.title.isEmpty ? "Untitled Recipe" : entry.title)
            Spacer()
            if let page = entry.page {
                Text("p. \(page)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
