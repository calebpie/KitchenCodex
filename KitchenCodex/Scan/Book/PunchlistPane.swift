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

/// An entry's mark: its recipe's state (ux-notes row 121).
struct StatusDot: View {
    let entry: BookEntry

    var body: some View {
        PunchlistMark(state: entry.recipe?.needsReview == true ? .needsReview : entry.status == .listed ? .listed : .captured)
    }
}

/// A punchlist entry's mark (ux-notes row 121, 04 §5.1 "Punchlist marks"): the empty circle until
/// it is captured, one tinted check once it is, reviewed or not, and the orange mark only while
/// its recipe needs review. Whether the cook reviewed a page is not something the list shows.
/// Shape and colour both say which.
struct PunchlistMark: View {
    enum State {
        case listed, captured, needsReview
    }

    let state: State

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch state {
        case .listed: "circle"
        case .captured: "checkmark.circle.fill"
        case .needsReview: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .listed: .secondary
        case .captured: .accentColor
        case .needsReview: .orange
        }
    }

    private var label: String {
        switch state {
        case .listed: "Not captured"
        case .captured: "Captured"
        case .needsReview: "Needs review"
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
