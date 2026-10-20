import Capture
import RecipeModel
import SwiftData
import SwiftUI

/// Cookbooks → Add → Add Cookbook (Flow C steps 1–2, 03 §3.7): type an ISBN or search by title,
/// confirm the book on its card, and it goes on the shelf with its cover. When nothing is found,
/// or the card is wrong, the details can be entered by hand. The barcode scanner sits beside the
/// ISBN field once the app may use the camera (`ISBNScanner`).
struct AddCookbookView: View {
    /// The new book, or the one already on the shelf with that ISBN; the shelf opens it once the
    /// sheet has gone.
    var onAdd: (Book) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]

    private enum Query: Equatable {
        case isbn(String)
        case title(String)
    }

    private enum Phase: Equatable {
        case idle
        case looking(Query)
        case found([BookCandidate], Query)
        case failed(BookLookupError, Query)
    }

    private enum Field { case isbn, title }

    @State private var isbnText = ""
    @State private var titleQuery = ""
    @State private var phase = Phase.idle
    @State private var work: Task<Void, Never>?
    /// The candidate being added while its cover downloads.
    @State private var addingID: BookCandidate.ID?
    /// Details by hand: the form in place of the lookup, and what it started from.
    @State private var manualDraft: BookDraft?
    @State private var manualStart: BookDraft?
    @State private var isConfirmingDiscard = false
    @State private var isScanning = false
    @FocusState private var focusedField: Field?

    /// Open Library, and Google Books once a key is configured (none is yet).
    private let lookup = BookLookup(googleBooksKey: Bundle.main.object(forInfoDictionaryKey: "GoogleBooksAPIKey") as? String)

    private var normalizedISBN: String? { ISBN.normalized(isbnText) }

    /// Ten or thirteen characters typed that aren't an ISBN: worth saying before the lookup.
    private var isISBNMistyped: Bool {
        let count = isbnText.filter { $0.isNumber || $0 == "X" || $0 == "x" }.count
        return (count == 10 || count >= 13) && normalizedISBN == nil
    }

    private var hasManualChanges: Bool { manualDraft != manualStart }

    /// What the details by hand start from: the ISBN and title the cook typed.
    private var prefill: BookDraft {
        BookDraft(title: titleQuery.trimmingCharacters(in: .whitespacesAndNewlines), isbn: normalizedISBN ?? "")
    }

    var body: some View {
        NavigationStack {
            Group {
                if manualDraft != nil {
                    BookInfoForm(draft: Binding { manualDraft ?? BookDraft() } set: { manualDraft = $0 })
                } else {
                    lookupForm
                }
            }
            .navigationTitle("Add Cookbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        if hasManualChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .keyboardShortcut(.cancelAction)
                    .confirmationDialog("Discard this cookbook?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                        Button("Discard", role: .destructive) { dismiss() }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                if let manualDraft {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add", role: .confirm) { add(manualDraft) }
                            .disabled(!manualDraft.canSave)
                    }
                }
            }
        }
        .interactiveDismissDisabled(hasManualChanges || addingID != nil)
        .fullScreenCover(isPresented: $isScanning) {
            ISBNScannerSheet { isbn in
                isScanning = false
                isbnText = isbn
                lookUpISBN()
            }
        }
        .onDisappear { work?.cancel() }
    }

    // MARK: - Lookup

    private var lookupForm: some View {
        Form {
            Section {
                HStack {
                    TextField("ISBN", text: $isbnText, prompt: Text("10 or 13 digits"))
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .isbn)
                        .accessibilityLabel("ISBN")
                    // Hidden until the app may use the camera.
                    if ISBNScanner.isAvailable {
                        Button("Scan Barcode", systemImage: "barcode.viewfinder") { isScanning = true }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
                Button("Look Up ISBN", systemImage: "magnifyingglass") { lookUpISBN() }
                    .disabled(normalizedISBN == nil)
            } header: {
                Text("ISBN")
            } footer: {
                if isISBNMistyped {
                    Text("Those digits aren't a valid ISBN. Check them against the barcode.")
                        .foregroundStyle(.red)
                } else {
                    Text("The number over the barcode on the back cover, or on the copyright page.")
                }
            }

            Section("Search by Title") {
                TextField("Title", text: $titleQuery)
                    .submitLabel(.search)
                    .focused($focusedField, equals: .title)
                    .onSubmit(searchTitle)
                Button("Search Titles", systemImage: "text.magnifyingglass") { searchTitle() }
                    .disabled(titleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            results
        }
    }

    @ViewBuilder
    private var results: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .looking:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking up…")
                        .foregroundStyle(.secondary)
                }
            }
        case let .found(candidates, query):
            Section {
                ForEach(candidates) { candidate in
                    BookCandidateCard(candidate: candidate, state: state(of: candidate)) {
                        add(candidate)
                    }
                }
            } header: {
                if case .title = query {
                    Text(candidates.count == 1 ? "1 Result" : "\(candidates.count) Results")
                } else {
                    Text("Found")
                }
            } footer: {
                Text("From \(candidates.first?.source.rawValue ?? "Open Library").")
            }
            Section {
                enterByHand(title: "Not It? Enter Details by Hand")
            }
        case let .failed(error, query):
            Section {
                Label(message(for: error, query: query), systemImage: error == .notFound ? "book.closed" : "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
                enterByHand(title: "Enter Details by Hand")
            }
        }
    }

    private func enterByHand(title: String) -> some View {
        Button(title, systemImage: "square.and.pencil") {
            work?.cancel()
            manualDraft = prefill
            manualStart = prefill
        }
    }

    private func message(for error: BookLookupError, query: Query) -> String {
        switch (error, query) {
        case (.notFound, .isbn): "No cookbook found for that ISBN."
        case let (.notFound, .title(title)): "No cookbook found for “\(title)”."
        case (.invalidISBN, _): "Those digits aren't a valid ISBN."
        case (.offline, _): "You appear to be offline. Try again when you're connected, or enter the details by hand."
        case (.badResponse, _): "Open Library didn't answer as expected. Try again later, or enter the details by hand."
        }
    }

    private func state(of candidate: BookCandidate) -> BookCandidateCard.State {
        if addingID == candidate.id { return .adding }
        if shelved(candidate) != nil { return .onShelf }
        return addingID == nil ? .ready : .disabled
    }

    /// The book already on the shelf with this ISBN.
    private func shelved(_ candidate: BookCandidate) -> Book? {
        guard let isbn = candidate.isbn13 else { return nil }
        return books.first { $0.isbn == isbn }
    }

    private func lookUpISBN() {
        guard let isbn = normalizedISBN else { return }
        run(.isbn(isbn)) { [lookup] () async throws(BookLookupError) -> [BookCandidate] in
            [try await lookup.lookup(isbn: isbn)]
        }
    }

    private func searchTitle() {
        let title = titleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        run(.title(title)) { [lookup] () async throws(BookLookupError) -> [BookCandidate] in
            try await lookup.search(title: title)
        }
    }

    private func run(_ query: Query, _ operation: @escaping () async throws(BookLookupError) -> [BookCandidate]) {
        work?.cancel()
        focusedField = nil
        phase = .looking(query)
        work = Task {
            do throws(BookLookupError) {
                let candidates = try await operation()
                guard !Task.isCancelled else { return }
                phase = .found(candidates, query)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error, query)
            }
        }
    }

    // MARK: - Adding

    /// Confirms a card: the book with its cover, downloaded and downsampled as recipe covers are.
    /// A book already on the shelf by that ISBN opens instead.
    private func add(_ candidate: BookCandidate) {
        if let book = shelved(candidate) {
            finish(book)
            return
        }
        addingID = candidate.id
        Task {
            var cover: Data?
            if let url = candidate.coverURL, let data = try? await lookup.coverImage(at: url) {
                cover = await ImageProcessing.jpeg(from: data, maxPixelSize: BookCover.maxPixelSize, quality: BookCover.quality)
            }
            let book = Book(title: candidate.title, author: candidate.authors.formatted(.list(type: .and)), isbn: candidate.isbn13)
            book.publicationYear = candidate.publicationYear
            book.coverImageData = cover
            modelContext.insert(book)
            try? modelContext.save()
            addingID = nil
            finish(book)
        }
    }

    /// Details by hand.
    private func add(_ draft: BookDraft) {
        let book = Book()
        draft.apply(to: book)
        modelContext.insert(book)
        try? modelContext.save()
        finish(book)
    }

    private func finish(_ book: Book) {
        onAdd(book)
        dismiss()
    }
}

/// A found book to confirm (Flow C step 2): cover, title, subtitle, author and year, with Add.
private struct BookCandidateCard: View {
    enum State {
        case ready
        /// Another card is being added.
        case disabled
        case adding
        /// A book with this ISBN is already on the shelf; the button opens it.
        case onShelf
    }

    let candidate: BookCandidate
    let state: State
    var onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: candidate.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Monogram(title: candidate.title)
            }
            .frame(width: 60, height: 90)
            .clipShape(.rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator, lineWidth: 0.5) }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.title)
                    .font(.headline)
                if let subtitle = candidate.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !candidate.authors.isEmpty {
                    Text(candidate.authors.formatted(.list(type: .and)))
                        .font(.subheadline)
                }
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            button
        }
        .padding(.vertical, 4)
    }

    /// "2015 · ISBN 9780393081084"
    private var detail: String? {
        let parts = [candidate.publicationYear.map(String.init), candidate.isbn13.map { "ISBN \($0)" }].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var button: some View {
        switch state {
        case .adding:
            ProgressView()
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Adding")
        case .onShelf:
            Button("On Shelf", action: onAdd)
                .buttonStyle(.bordered)
                .accessibilityHint("Opens the cookbook already on your shelf.")
        case .ready, .disabled:
            Button("Add", action: onAdd)
                .buttonStyle(.borderedProminent)
                .disabled(state == .disabled)
                .accessibilityLabel("Add \(candidate.title)")
        }
    }
}
