import RecipeModel
import SwiftData
import SwiftUI

/// The recipe list read off the contents pages, corrected inline before the session starts (02
/// Flow C step 3): edit a title or a page, add a recipe, delete one, move one to another section,
/// rename a section, merge it with the one before or after, and confirm its course. Every change
/// is saved as it is made. A title's edit ends on Return, on a tap outside it and on the
/// keyboard's Done (ux-notes row 120). Chapters alone are a list to start scanning from (row 117).
/// Build the Recipe List ends here, and Book detail's More → Edit Recipe List opens it again.
struct PunchlistEditorView: View {
    let book: Book
    /// Build the Recipe List: Start Scanning and Done for Now. Nil shows Done.
    var onStartScanning: (() -> Void)?
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var renaming: BookSection?
    @State private var newTitle = ""
    @FocusState private var focused: EntryField?
    /// Where the field under edit is, so a tap anywhere else ends the edit.
    @State private var editingFrame: CGRect = .zero

    /// A title or a page under edit.
    enum EntryField: Hashable {
        case title(UUID), page(UUID)
    }

    private var session: BookScanSession { BookScanStore.shared.session(for: book, context: modelContext) }

    var body: some View {
        let sections = book.orderedSections
        let entries = book.orderedEntries
        List {
            Section {
                Text(summary(sections: sections.count, entries: entries))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Correct anything the contents pages read wrong: tap a title or page to edit it, swipe to delete or move a recipe, and use a section's menu to rename or merge it.")
            }
            ForEach(Array(sections.enumerated()), id: \.element.id) { position, section in
                Section {
                    ForEach(section.orderedEntries) { entry in
                        EntryEditorRow(entry: entry, focused: $focused, onCommit: commit) { editingFrame = $0 }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                            }
                            .swipeActions(edge: .leading) {
                                if sections.count > 1 {
                                    Menu {
                                        ForEach(sections.filter { $0.id != section.id }) { other in
                                            Button(other.displayTitle) { move(entry, to: other) }
                                        }
                                    } label: {
                                        Label("Move", systemImage: "arrow.turn.down.right")
                                    }
                                    .tint(.indigo)
                                }
                            }
                            .contextMenu {
                                Menu("Move to Section") {
                                    ForEach(sections.filter { $0.id != section.id }) { other in
                                        Button(other.displayTitle) { move(entry, to: other) }
                                    }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                            }
                    }
                    Button("Add Recipe", systemImage: "plus") { add(to: section) }
                } header: {
                    HStack(spacing: 8) {
                        Text(section.displayTitle + (section.startPage.map { "  p. \($0)" } ?? ""))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CourseChip(course: session.course(for: section)) { session.setCourse($0, for: section) }
                        Menu {
                            Button("Rename…", systemImage: "pencil") {
                                newTitle = section.title
                                renaming = section
                            }
                            if position > 0 {
                                Button("Merge with \(sections[position - 1].displayTitle)", systemImage: "arrow.up.to.line") { merge(section, into: sections[position - 1]) }
                            }
                            if position + 1 < sections.count {
                                Button("Merge with \(sections[position + 1].displayTitle)", systemImage: "arrow.down.to.line") { merge(sections[position + 1], into: section) }
                            }
                            Divider()
                            Button("Delete Section", systemImage: "trash", role: .destructive) { delete(section) }
                        } label: {
                            Label("Section Actions", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            Section {
                Button("Add Section", systemImage: "plus.rectangle.on.rectangle") { addSection() }
            }
        }
        // A tap outside the field under edit ends the edit (ux-notes row 120); one on another
        // field moves the edit there, so the field is let go only if the tap left focus alone.
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
            guard let editing = focused, !editingFrame.contains(tap.location) else { return }
            Task { @MainActor in
                await Task.yield()
                if focused == editing { focused = nil }
            }
        })
        .navigationTitle("Recipe List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
            if let onStartScanning {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done for Now") { commit(); onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Chapters alone are a list: recipes file in them as they are scanned.
                    Button("Start Scanning", role: .confirm) { commit(); onStartScanning() }
                        .disabled(sections.isEmpty)
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { commit(); onDone() }
                }
            }
        }
        .alert("Rename Section", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }) {
            TextField("Section", text: $newTitle)
            Button("Rename") {
                renaming?.title = newTitle.trimmingCharacters(in: .whitespaces)
                renaming = nil
                commit()
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func summary(sections: Int, entries: [BookEntry]) -> String {
        let paged = entries.count { $0.page != nil }
        let chapters = sections == 1 ? "1 section" : "\(sections) sections"
        let recipes = entries.count == 1 ? "1 recipe" : "\(entries.count) recipes"
        return entries.isEmpty ? "\(chapters), no recipes listed; recipes are added as you scan" : "\(chapters) · \(recipes) · \(paged) with a page number"
    }

    private func commit() {
        try? modelContext.save()
    }

    private func add(to section: BookSection) {
        let entry = BookEntry(title: "", page: nil)
        entry.sortOrder = (section.orderedEntries.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(entry)
        entry.section = section
        commit()
        focused = .title(entry.id)
    }

    private func delete(_ entry: BookEntry) {
        modelContext.delete(entry)
        commit()
    }

    private func move(_ entry: BookEntry, to section: BookSection) {
        // In page order among the section's entries.
        let later = section.orderedEntries.first { ($0.page ?? .max) > (entry.page ?? .max) }
        let order = later?.sortOrder ?? ((section.orderedEntries.map(\.sortOrder).max() ?? -1) + 1)
        for other in section.orderedEntries where other.sortOrder >= order { other.sortOrder += 1 }
        entry.sortOrder = order
        entry.section = section
        commit()
    }

    /// `section`'s entries join `target` after its own, and `section` goes.
    private func merge(_ section: BookSection, into target: BookSection) {
        var order = (target.orderedEntries.map(\.sortOrder).max() ?? -1) + 1
        for entry in section.orderedEntries {
            entry.sortOrder = order
            order += 1
            entry.section = target
        }
        if let page = section.startPage { target.startPage = min(target.startPage ?? page, page) }
        modelContext.delete(section)
        commit()
    }

    private func delete(_ section: BookSection) {
        modelContext.delete(section)
        commit()
    }

    private func addSection() {
        let section = BookSection(title: "New Section", sortOrder: (book.orderedSections.map(\.sortOrder).max() ?? -1) + 1)
        modelContext.insert(section)
        section.book = book
        commit()
        newTitle = ""
        renaming = section
    }
}

/// One entry, its title and page edited in place. The title wraps; Return ends its edit, the
/// break taken out, as review's in-place edits do (ux-notes rows 70, 120).
private struct EntryEditorRow: View {
    @Bindable var entry: BookEntry
    var focused: FocusState<PunchlistEditorView.EntryField?>.Binding
    var onCommit: () -> Void
    /// The row's frame while one of its fields is under edit.
    var onEditingFrame: (CGRect) -> Void

    @State private var page = ""
    @State private var frame: CGRect = .zero

    private var isEditing: Bool {
        focused.wrappedValue == .title(entry.id) || focused.wrappedValue == .page(entry.id)
    }

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(entry: entry)
            TextField("Recipe title", text: $entry.title, axis: .vertical)
                .focused(focused, equals: .title(entry.id))
                .submitLabel(.done)
                .onSubmit { focused.wrappedValue = nil }
                .onChange(of: entry.title) { _, title in
                    guard title.contains(where: \.isNewline) else { return }
                    entry.title = title.split(whereSeparator: \.isNewline).joined(separator: " ")
                    focused.wrappedValue = nil
                }
            TextField("Page", text: $page)
                .focused(focused, equals: .page(entry.id))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                .onChange(of: page) { _, text in
                    let digits = text.filter(\.isNumber)
                    if digits != text { page = digits }
                    entry.page = Int(digits)
                }
                .accessibilityLabel("Page")
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            self.frame = frame
            if isEditing { onEditingFrame(frame) }
        }
        .onChange(of: isEditing) { _, editing in
            if editing { onEditingFrame(frame) } else { onCommit() }
        }
        .onAppear { page = entry.page.map(String.init) ?? "" }
    }
}
