import Capture
import PhotosUI
import RecipeModel
import SwiftData
import SwiftUI
import UIKit

/// A book's details as the cook edits them: Edit Book Info, and Add Cookbook's details by hand.
struct BookDraft: Equatable {
    enum Cover: Equatable {
        case unchanged
        /// A new cover, downsampled as recipe covers are.
        case replaced(Data)
        case removed
    }

    var title = ""
    var author = ""
    var year = ""
    var isbn = ""
    var cover = Cover.unchanged

    init(title: String = "", isbn: String = "") {
        self.title = title
        self.isbn = isbn
    }

    init(book: Book) {
        title = book.title
        author = book.author
        year = book.publicationYear.map(String.init) ?? ""
        isbn = book.isbn ?? ""
    }

    private var trimmedISBN: String { isbn.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The ISBN as ISBN-13, nil when blank; blank or valid is fine, anything else is not.
    var normalizedISBN: String? { ISBN.normalized(trimmedISBN) }
    var isISBNValid: Bool { trimmedISBN.isEmpty || normalizedISBN != nil }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isISBNValid
    }

    /// Writes the draft into `book`.
    func apply(to book: Book) {
        book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        book.publicationYear = Int(year.trimmingCharacters(in: .whitespacesAndNewlines))
        book.isbn = normalizedISBN
        switch cover {
        case .unchanged: break
        case let .replaced(data): book.coverImageData = data
        case .removed: book.coverImageData = nil
        }
    }
}

/// The book's fields as a form: cover (Photos), title, author, year and ISBN.
struct BookInfoForm: View {
    @Binding var draft: BookDraft
    /// The cover already saved, shown until the draft changes it.
    var savedCover: Data?

    @State private var photoItem: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var isLoadingPhoto = false
    @State private var photoFailed = false

    var body: some View {
        Form {
            coverSection

            Section {
                TextField("Title", text: $draft.title, axis: .vertical)
                    .font(.headline)
                TextField("Author", text: $draft.author)
                    .textContentType(.name)
            }

            Section {
                LabeledContent("Year") {
                    TextField("Year", text: $draft.year, prompt: Text("Optional"))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: draft.year) { _, year in
                            let digits = String(year.filter(\.isASCII).filter(\.isNumber).prefix(4))
                            if digits != year { draft.year = digits }
                        }
                }
                LabeledContent("ISBN") {
                    TextField("ISBN", text: $draft.isbn, prompt: Text("10 or 13 digits"))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                if !draft.isISBNValid {
                    Text("That isn't a valid ISBN. Check the 10 or 13 digits under the barcode or on the copyright page.")
                        .foregroundStyle(.red)
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .task {
            if let savedCover {
                preview = await ImageProcessing.thumbnail(from: savedCover, maxPixelSize: 600)
            }
        }
    }

    private var coverSection: some View {
        Section {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(.rect(cornerRadius: 6))
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .accessibilityLabel("Cover")
            }
            // PhotosPicker's label closure is nonisolated, so read the state here.
            let title = preview == nil ? "Add Cover" : "Change Cover"
            let isLoading = isLoadingPhoto
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                HStack {
                    Label(title, systemImage: "photo")
                    if isLoading {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            if preview != nil {
                Button("Remove Cover", systemImage: "trash", role: .destructive) {
                    preview = nil
                    photoItem = nil
                    draft.cover = savedCover == nil ? .unchanged : .removed
                }
            }
        } footer: {
            if photoFailed {
                Text("That photo couldn't be read. Try another.")
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        photoFailed = false
        defer { isLoadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let cover = await ImageProcessing.jpeg(from: data, maxPixelSize: BookCover.maxPixelSize, quality: BookCover.quality) else {
            photoFailed = true
            return
        }
        draft.cover = .replaced(cover)
        preview = await ImageProcessing.thumbnail(from: cover, maxPixelSize: 600)
    }
}

/// How book covers are stored: one JPEG at the size and quality of a recipe's cover copy.
enum BookCover {
    static let maxPixelSize: CGFloat = 900
    static let quality: CGFloat = 0.8
}

/// Book detail → More → Edit Book Info (03 §3.7): the book's fields in a sheet. Cancel with
/// changes asks first, and so does Escape.
struct BookInfoEditor: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: BookDraft
    @State private var isConfirmingDiscard = false
    private let original: BookDraft

    init(book: Book) {
        self.book = book
        let draft = BookDraft(book: book)
        _draft = State(initialValue: draft)
        original = draft
    }

    private var hasChanges: Bool { draft != original }

    var body: some View {
        NavigationStack {
            BookInfoForm(draft: $draft, savedCover: book.coverImageData)
                .navigationTitle("Edit Book Info")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                        }
                        .keyboardShortcut(.cancelAction)
                        .confirmationDialog("Discard changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing", role: .cancel) {}
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", role: .confirm) {
                            draft.apply(to: book)
                            try? modelContext.save()
                            dismiss()
                        }
                        .disabled(!hasChanges || !draft.canSave)
                    }
                }
        }
        .interactiveDismissDisabled(hasChanges)
    }
}
