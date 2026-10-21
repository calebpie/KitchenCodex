import RecipeModel
import SwiftUI

/// The session's punchlist (03 §3.8): the book's sections with their course and "8 of 12", each
/// entry with its status dot and page, the current item highlighted. Tapping an entry makes it the
/// current item. On iPad the left region; on iPhone a sheet from the header.
struct PunchlistPane: View {
    let session: BookScanSession
    /// iPhone's sheet closes once an entry is picked.
    var onSelect: (() -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(session.book.orderedSections) { section in
                    Section {
                        ForEach(section.orderedEntries) { entry in
                            Button {
                                session.select(entry)
                                onSelect?()
                            } label: {
                                PunchlistEntryLine(entry: entry, isCurrent: entry.id == session.state.currentEntry)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(entry.id == session.state.currentEntry ? Color.accentColor.opacity(0.16) : nil)
                            .id(entry.id)
                            .accessibilityAddTraits(entry.id == session.state.currentEntry ? .isSelected : [])
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Text(section.displayTitle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            CourseChip(course: session.course(for: section)) { session.setCourse($0, for: section) }
                            Text("\(section.capturedCount) of \(section.entries?.count ?? 0)")
                                .monospacedDigit()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onAppear { scroll(proxy) }
            .onChange(of: session.state.currentEntry) { _, _ in withAnimation { scroll(proxy) } }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        if let current = session.state.currentEntry { proxy.scrollTo(current, anchor: .center) }
    }
}

/// One entry: its status dot, title and page.
struct PunchlistEntryLine: View {
    let entry: BookEntry
    var isCurrent = false

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(entry: entry)
            Text(entry.displayTitle)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(entry.status == .listed ? .primary : .secondary)
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

/// Listed, captured, needing review, reviewed: shape and colour both say which.
struct StatusDot: View {
    let entry: BookEntry

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var needsLook: Bool { entry.recipe?.needsReview == true }

    private var symbol: String {
        if needsLook { return "exclamationmark.circle.fill" }
        switch entry.status {
        case .listed: return "circle"
        case .captured: return "circle.inset.filled"
        case .reviewed: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        if needsLook { return .orange }
        switch entry.status {
        case .listed: return .secondary
        case .captured: return .accentColor
        case .reviewed: return .green
        }
    }

    private var label: String {
        if needsLook { return "Needs review" }
        switch entry.status {
        case .listed: return "Not captured"
        case .captured: return "Captured"
        case .reviewed: return "Reviewed"
        }
    }
}

/// A section's course (ux-notes row 73): the chapter's default from its title, confirmed or changed
/// inline; recipes saved from the section take it.
struct CourseChip: View {
    let course: String?
    var onChange: (String?) -> Void

    var body: some View {
        Menu {
            Picker("Course", selection: Binding { course } set: { onChange($0) }) {
                Text("No Course").tag(String?.none)
                ForEach(RecipeCourse.standard, id: \.self) { Text($0).tag(Optional($0)) }
            }
        } label: {
            Text(course ?? "No Course")
                .font(.caption.weight(.semibold))
                .textCase(nil)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(course == nil ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(Color.accentColor.opacity(0.18)), in: .capsule)
                .foregroundStyle(course == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        }
        .accessibilityLabel("Course: \(course ?? "none")")
        .accessibilityHint("Recipes saved from this chapter take this course.")
    }
}
