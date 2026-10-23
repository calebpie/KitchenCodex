import RecipeModel
import SwiftData
import SwiftUI

/// What the queue holds: a recipe in scan review, or a reference (a glossary, a chapter, a
/// technique) with its page beside its sections.
enum ReviewTarget: Identifiable {
    case recipe(Recipe)
    case reference(Reference)

    var id: UUID {
        switch self {
        case let .recipe(recipe): recipe.id
        case let .reference(reference): reference.id
        }
    }

    var title: String {
        switch self {
        case let .recipe(recipe): recipe.title
        case let .reference(reference): reference.title
        }
    }

    var recipe: Recipe? {
        if case let .recipe(recipe) = self { return recipe }
        return nil
    }
}

extension Book {
    /// The queue (02 Flow C step 7): recipes waiting for a look, then references, each oldest first.
    var reviewTargets: [ReviewTarget] {
        reviewQueue.map(ReviewTarget.recipe) + ReferenceSaving.reviewQueue(for: self).map(ReviewTarget.reference)
    }
}

/// The review queue (02 Flow C step 7, 03 §3.8): the book's first recipe of each layout, which
/// confirms it, and the captures the cook flagged or that read with low confidence, one after
/// another in scan review over their stored pages; a reference the session marked for a look
/// shows its page beside its title and sections (slice 7). Save reviews one (its entry
/// `reviewed`, its layout confirmed) and moves to the next; Skip leaves it in the queue and is off
/// on the last, and Save on the last closes the review, back to the camera when opened from the
/// session and to Book detail otherwise (ux-notes rows 137, 168). More holds Rescan, back to the
/// camera at the recipe's page, and Discard Scan, the capture and its recipe gone and the entry
/// listed again (row 136). Under the page, the title as a plain centred caption with its page in
/// italics (row 138). Opened at the end of a session or from Book detail's "N need review".
struct BookReviewQueueView: View {
    let book: Book
    /// Rescan: the book session's camera at the recipe's entry (nil when it is on no list), the
    /// recipe named so the next capture replaces it (ux-notes row 164).
    var onRescan: (BookEntry?, Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// The queue as it stood when the sheet opened, so a saved recipe keeps its place in the count.
    @State private var queue: [ReviewTarget] = []
    @State private var position = 0
    @State private var model: ScanReviewModel?
    /// A reference's fields under review.
    @State private var draft = ReferenceDraft()
    @State private var original = ReferenceDraft()
    @State private var isSaving = false
    @State private var reviewedCount = 0
    @State private var isConfirmingClose = false

    private var target: ReviewTarget? { queue.indices.contains(position) ? queue[position] : nil }
    private var current: Recipe? { target?.recipe }
    private var hasChanges: Bool {
        if let model { return model.hasChanges }
        if case .reference = target { return draft != original }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                if let model, let current {
                    ScanReviewView(model: model, book: book, stored: current, onRescan: { onRescan(current.bookEntry, current) }, rescansWithCamera: true,
                                   onDiscard: { discard(current) }, offersSkip: false)
                        .id(ObjectIdentifier(model))
                        .disabled(isSaving)
                } else if case let .reference(reference) = target {
                    ReferenceReviewView(reference: reference, draft: $draft)
                        .id(reference.id)
                        .disabled(isSaving)
                } else {
                    // Only when the queue was empty to begin with: the last Save closes the review
                    // (ux-notes row 168).
                    ContentUnavailableView {
                        Label("Nothing to Review", systemImage: "checkmark.seal")
                    } description: {
                        Text("Every recipe scanned from this book has been looked at.")
                    }
                }
            }
            .navigationTitle(target == nil ? "Review" : "Review \(position + 1) of \(queue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .cancel) {
                        if hasChanges { isConfirmingClose = true } else { dismiss() }
                    }
                    .keyboardShortcut(.cancelAction)
                    // An alert, so Keep Reviewing always draws over the full-screen page (ux-notes row 158).
                    .alert("Discard changes?", isPresented: $isConfirmingClose) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                        Button("Keep Reviewing", role: .cancel) {}
                    }
                }
                if target != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        // Saving without changes is the cook saying it looks right.
                        Button(position + 1 < queue.count ? "Save & Next" : "Save", role: .confirm) { save() }
                            .disabled(isSaving || !canSave)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Previous", systemImage: "chevron.backward") { go(to: position - 1) }
                            .disabled(position == 0)
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    // A plain caption, no bubble (ux-notes row 138).
                    ToolbarItem(placement: .bottomBar) {
                        caption
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        // Nothing after the last: the end comes through Save (ux-notes row 137).
                        Button("Skip", systemImage: "chevron.forward") { go(to: position + 1) }
                            .labelStyle(.titleAndIcon)
                            .disabled(position + 1 >= queue.count)
                    }
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .onAppear {
            guard queue.isEmpty else { return }
            queue = book.reviewTargets
            load()
        }
    }

    /// The title in footnote text, its page after it in italics: "Leek Soup *p. 90*".
    private var caption: some View {
        let page: Int? = switch target {
        case let .recipe(recipe): recipe.pageNumber
        case let .reference(reference): reference.source?.firstPage
        case nil: nil
        }
        // The title gives way to the page when the bar is short of room.
        return HStack(spacing: 6) {
            Text(target?.title ?? "")
                .lineLimit(1)
            if let page {
                Text("p. \(page)")
                    .italic()
                    .fixedSize()
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    /// Discard Scan: the capture and its recipe go, the entry is listed again, and the queue moves
    /// on to the next.
    private func discard(_ recipe: Recipe) {
        BookScanStore.shared.session(for: book, context: modelContext).discardScan(of: recipe)
        if queue.indices.contains(position) { queue.remove(at: position) }
        load()
    }

    private var canSave: Bool {
        switch target {
        case .recipe: model?.recipe.title?.text.trimmed.isEmpty == false
        case .reference: draft.canSave
        case nil: false
        }
    }

    private func load() {
        model = current.flatMap(ScanReviewModel.init(recipe:))
        if case let .reference(reference) = target {
            draft = ReferenceDraft(reference: reference)
            original = draft
        }
    }

    /// The next (or previous) recipe; past the last, the review closes (ux-notes row 168).
    private func go(to index: Int) {
        guard index < queue.count else {
            dismiss()
            return
        }
        position = max(0, index)
        load()
    }

    private func save() {
        switch target {
        case let .recipe(recipe):
            guard let model else { return }
            isSaving = true
            Task {
                await ScanSaving.saveReview(model, of: recipe, images: ScanSaving.PageImages(), in: modelContext)
                reviewedCount += 1
                isSaving = false
                go(to: position + 1)
            }
        case let .reference(reference):
            draft.apply(to: reference, in: modelContext)
            ReferenceSaving.markReviewed(reference, in: modelContext)
            reviewedCount += 1
            go(to: position + 1)
        case nil:
            break
        }
    }
}
