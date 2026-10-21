import RecipeModel
import SwiftData
import SwiftUI

/// The review queue (02 Flow C step 7, 03 §3.8): the book's first recipe of each layout, which
/// confirms it, and the captures the cook flagged or that read with low confidence, one after
/// another in scan review over their stored pages. Save reviews one (its entry `reviewed`, its
/// layout confirmed) and moves to the next; Skip leaves it in the queue. Opened at the end of a
/// session or from Book detail's "N need review".
struct BookReviewQueueView: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// The queue as it stood when the sheet opened, so a saved recipe keeps its place in the count.
    @State private var queue: [Recipe] = []
    @State private var position = 0
    @State private var model: ScanReviewModel?
    @State private var isSaving = false
    @State private var reviewedCount = 0
    @State private var isConfirmingClose = false

    private var current: Recipe? { queue.indices.contains(position) ? queue[position] : nil }

    var body: some View {
        NavigationStack {
            Group {
                if let model, current != nil {
                    ScanReviewView(model: model, bookTitle: book.displayTitle, offersSkip: false)
                        .id(ObjectIdentifier(model))
                        .disabled(isSaving)
                } else {
                    ContentUnavailableView {
                        Label(reviewedCount > 0 ? "Review Done" : "Nothing to Review", systemImage: "checkmark.seal")
                    } description: {
                        Text(reviewedCount > 0
                             ? (reviewedCount == 1 ? "1 recipe reviewed." : "\(reviewedCount) recipes reviewed.") + (book.reviewQueue.isEmpty ? "" : " The ones you skipped wait in the book.")
                             : "Every recipe scanned from this book has been looked at.")
                    }
                }
            }
            .navigationTitle(current == nil ? "Review" : "Review \(position + 1) of \(queue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .cancel) {
                        if model?.hasChanges == true { isConfirmingClose = true } else { dismiss() }
                    }
                    .keyboardShortcut(.cancelAction)
                    .confirmationDialog("Discard changes to this recipe?", isPresented: $isConfirmingClose, titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                        Button("Keep Reviewing", role: .cancel) {}
                    }
                }
                if current != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        // Saving without changes is the cook saying it looks right.
                        Button(position + 1 < queue.count ? "Save & Next" : "Save", role: .confirm) { save() }
                            .disabled(isSaving || model?.recipe.title?.text.trimmed.isEmpty != false)
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("Previous", systemImage: "chevron.backward") { go(to: position - 1) }
                            .disabled(position == 0)
                        Spacer()
                        Text(current?.title ?? "")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Skip", systemImage: "chevron.forward") { go(to: position + 1) }
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .interactiveDismissDisabled(model?.hasChanges == true)
        .onAppear {
            guard queue.isEmpty else { return }
            queue = book.reviewQueue
            load()
        }
    }

    private func load() {
        model = current.flatMap(ScanReviewModel.init(recipe:))
    }

    private func go(to index: Int) {
        position = max(0, min(index, queue.count))
        load()
    }

    private func save() {
        guard let model, let recipe = current else { return }
        isSaving = true
        Task {
            await ScanSaving.saveReview(model, of: recipe, images: ScanSaving.PageImages(), in: modelContext)
            reviewedCount += 1
            isSaving = false
            go(to: position + 1)
        }
    }
}
