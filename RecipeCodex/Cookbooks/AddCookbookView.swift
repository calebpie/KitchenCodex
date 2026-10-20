import Capture
import OSLog
import PhotosUI
import RecipeModel
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Cookbooks → Add → Add Cookbook (Flow C steps 1–2, 03 §3.7), barcode first (04 §5.1 "Add
/// Cookbook", ux-notes rows 47 and 48): a photo of the barcode on the back cover, from Photos or
/// Files, is read for its ISBN, looked up, and the book confirmed on its card goes on the shelf
/// with its cover. The live scanner sits first once the device can scan (slice 4); there is no
/// typed ISBN and no title search. When nothing is found, or the card is wrong, the details can be
/// entered by hand. Which book? opens it for a new book too.
struct AddCookbookView: View {
    /// The new book, or the one already on the shelf with that ISBN; the shelf opens it once the
    /// sheet has gone.
    var onAdd: (Book) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]

    private enum Phase: Equatable {
        case idle
        case reading
        /// The photo has no barcode that reads as an ISBN.
        case noBarcode
        case looking(String)
        case found(BookCandidate)
        case failed(BookLookupError, String)
    }

    @State private var phase = Phase.idle
    @State private var work: Task<Void, Never>?
    @State private var isAdding = false
    /// Details by hand: the form in place of the lookup, and what it started from.
    @State private var manualDraft: BookDraft?
    @State private var manualStart: BookDraft?
    @State private var isConfirmingDiscard = false
    @State private var isScanning = false
    @State private var isChoosingPhoto = false
    @State private var isChoosingFile = false
    @State private var photoItem: PhotosPickerItem?

    /// Open Library, and Google Books once a key is configured (none is yet).
    private let lookup = BookLookup(googleBooksKey: Bundle.main.object(forInfoDictionaryKey: "GoogleBooksAPIKey") as? String)

    private var hasManualChanges: Bool { manualDraft != manualStart }

    /// The ISBN read, which details by hand start from.
    private var readISBN: String? {
        switch phase {
        case let .looking(isbn), let .failed(_, isbn): isbn
        case let .found(candidate): candidate.isbn13
        default: nil
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if manualDraft != nil {
                    BookInfoForm(draft: Binding { manualDraft ?? BookDraft() } set: { manualDraft = $0 })
                } else {
                    barcodeForm
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
        .interactiveDismissDisabled(hasManualChanges || isAdding)
        .fullScreenCover(isPresented: $isScanning) {
            ISBNScannerSheet { isbn in
                isScanning = false
                lookUp(isbn)
            }
        }
        .photosPicker(isPresented: $isChoosingPhoto, selection: $photoItem, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            read {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try? Data(contentsOf: url)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            read { try? await item.loadTransferable(type: Data.self) }
        }
        .onDisappear { work?.cancel() }
    }

    // MARK: - The barcode

    private var barcodeForm: some View {
        Form {
            Section {
                // The live scanner, once the device can scan (slice 4); never on the simulator.
                if ISBNScanner.isAvailable {
                    Button("Scan Barcode", systemImage: "barcode.viewfinder") { isScanning = true }
                }
                Button("Choose Photo", systemImage: "photo") { isChoosingPhoto = true }
                Button("Choose File", systemImage: "folder") { isChoosingFile = true }
            } header: {
                Text("Barcode")
            } footer: {
                Text("A photo of the barcode on the back cover. Recipe Codex reads the ISBN under it and finds the book.")
            }
            .disabled(phase == .reading || isAdding)

            results
        }
    }

    @ViewBuilder
    private var results: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .reading:
            progress("Reading the barcode…")
        case let .looking(isbn):
            progress("Looking up ISBN \(isbn)…")
        case .noBarcode:
            Section {
                Label("No ISBN barcode could be read in that photo. Try a closer, straighter photo of the back cover.", systemImage: "barcode")
                    .foregroundStyle(.secondary)
                enterByHand(title: "Enter Details by Hand")
            }
        case let .found(candidate):
            Section {
                BookCandidateCard(candidate: candidate, state: state(of: candidate)) {
                    add(candidate)
                }
            } header: {
                Text("Found")
            } footer: {
                Text("From \(candidate.source.rawValue).")
            }
            Section {
                enterByHand(title: "Not It? Enter Details by Hand")
            }
        case let .failed(error, _):
            Section {
                Label(message(for: error), systemImage: error == .notFound ? "book.closed" : "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
                enterByHand(title: "Enter Details by Hand")
            }
        }
    }

    private func progress(_ text: String) -> some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(text)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func enterByHand(title: String) -> some View {
        Button(title, systemImage: "square.and.pencil") {
            work?.cancel()
            let start = BookDraft(isbn: readISBN ?? "")
            manualDraft = start
            manualStart = start
        }
    }

    private func message(for error: BookLookupError) -> String {
        switch error {
        case .notFound: "No cookbook found for that ISBN."
        case .invalidISBN: "That barcode isn't a valid ISBN."
        case .offline: "You appear to be offline. Try again when you're connected, or enter the details by hand."
        case .badResponse: "Open Library didn't answer as expected. Try again later, or enter the details by hand."
        }
    }

    private func state(of candidate: BookCandidate) -> BookCandidateCard.State {
        if isAdding { return .adding }
        if shelved(candidate) != nil { return .onShelf }
        return .ready
    }

    /// The book already on the shelf with this ISBN.
    private func shelved(_ candidate: BookCandidate) -> Book? {
        guard let isbn = candidate.isbn13 else { return nil }
        return books.first { $0.isbn == isbn }
    }

    /// Reads the barcode off the photo `load` gives, then looks its ISBN up.
    private func read(_ load: @escaping () async -> Data?) {
        work?.cancel()
        phase = .reading
        work = Task {
            guard let data = await load() else {
                phase = .noBarcode
                return
            }
            let isbn = await Self.isbn(in: data)
            guard !Task.isCancelled else { return }
            if let isbn { lookUp(isbn) } else { phase = .noBarcode }
        }
    }

    /// Vision's barcode reading, off the main actor. Why a photo gave no ISBN goes to the log
    /// (category "books").
    @concurrent
    nonisolated private static func isbn(in data: Data) async -> String? {
        let url = FileManager.default.temporaryDirectory.appending(path: "barcode-\(UUID().uuidString)")
        guard (try? data.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let isbn = try await ISBNBarcode.read(contentsOf: url)
            if isbn == nil { logger.info("Add Cookbook: no ISBN barcode in a \(data.count) byte photo") }
            return isbn
        } catch {
            logger.error("Add Cookbook: the barcode photo couldn't be read: \(error, privacy: .public)")
            return nil
        }
    }

    nonisolated private static let logger = Logger(subsystem: "com.calebpietrafesa.RecipeCodex", category: "books")

    private func lookUp(_ isbn: String) {
        work?.cancel()
        phase = .looking(isbn)
        work = Task { [lookup] in
            do throws(BookLookupError) {
                let candidate = try await lookup.lookup(isbn: isbn)
                guard !Task.isCancelled else { return }
                phase = .found(candidate)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error, isbn)
            }
        }
    }

    // MARK: - Adding

    /// Confirms the card: the book with its cover, downloaded and downsampled as recipe covers are.
    /// A book already on the shelf by that ISBN opens instead.
    private func add(_ candidate: BookCandidate) {
        if let book = shelved(candidate) {
            finish(book)
            return
        }
        isAdding = true
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
            isAdding = false
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
        case .ready:
            Button("Add", action: onAdd)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add \(candidate.title)")
        }
    }
}
