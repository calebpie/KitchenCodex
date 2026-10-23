import Foundation
import Testing

/// The private page photos in `Docs/Fixtures/Private/Pages` (copyrighted cookbooks, gitignored) and
/// the committed manifest that says what each should read as: slugs, ISBNs, file names, kinds,
/// gate readings, page numbers and counts, never page text.
enum PageFixtures {
    /// `Docs/Fixtures/Private/Pages`, found by walking up from this file as `Fixtures` finds the
    /// saved web pages. Nil in CI and cloud checkouts.
    static let pagesDirectory: URL? = {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appending(path: "Docs/Fixtures/Private/Pages")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }()

    static var available: Bool { pagesDirectory != nil }

    static let skipReason: Comment = "Docs/Fixtures/Private/Pages is not in this checkout (the page photos are copyrighted and gitignored)"

    /// `Docs/Fixtures/Private/Review`, where the report goes (gitignored with the rest).
    static var reviewDirectory: URL? {
        pagesDirectory?.deletingLastPathComponent().appending(path: "Review")
    }

    struct Book {
        /// "bouchon", "nobu-west".
        var slug: String
        var folder: URL
        /// Photos in capture order (file name order); the first is the ISBN barcode.
        var files: [URL]
    }

    /// Each book folder (not `Raw/`, an earlier DNG shoot that is not a fixture).
    static func books() -> [Book] {
        guard let root = pagesDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        return names.sorted().compactMap { name in
            guard name != "Raw", !name.hasPrefix(".") else { return nil }
            let folder = root.appending(path: name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { ["heic", "jpg", "jpeg", "png"].contains(($0 as NSString).pathExtension.lowercased()) }
                .sorted()
                .map { folder.appending(path: $0) }
            return Book(slug: name.lowercased().replacingOccurrences(of: " ", with: "-"), folder: folder, files: files)
        }
    }

    // MARK: - Manifest

    struct RecipeCounts: Codable, Sendable, Equatable {
        var ingredients: Int
        var steps: Int
    }

    /// What a contents page reads as (`ContentsReader`): its chapters, its entries, and the entries
    /// with a page number; for an index page, its index entries. Counts only, never a title.
    struct ContentsCounts: Codable, Sendable, Equatable {
        var sections: Int
        var entries: Int
        var paged: Int
    }

    /// One photo: what it is and what it should read as. No page text.
    struct Entry: Codable, Sendable, CustomTestStringConvertible {
        var slug: String
        var isbn: String
        var file: String
        /// recipe | spread-start | spread-middle | spread-end | contents | index | sources | photo |
        /// glossary (its entries the sections) | reference (a chapter opener, a technique) |
        /// bad-capture | other (the ISBN barcode photo is "other").
        var kind: String
        /// The gate's expected reading: sharp | holdStill | cleanTheLens.
        var gate: String
        /// The page number printed on the page, when the reading finds it.
        var page: Int?
        /// For a recipe page or a spread's first page: each recipe's ingredient and step counts as
        /// read (a spread's are the stitched recipe's).
        var recipes: [RecipeCounts]?
        /// For a contents page: what its punchlist reading counts.
        var contents: ContentsCounts?
        /// For a glossary or other reference page: its sections as read (a glossary's entries).
        var sections: Int?
        /// For a Sources page: the suppliers it reads into.
        var suppliers: Int?
        /// For an index page: a lower bound on the entries the page prints, counted as its lines
        /// that end in a page reference in the fuller of the Mac's and the phone's readings
        /// (ux-notes row 143); the readings are measured against it.
        var printed: Int?
        /// False where the counts are the reading's and could not be checked against the page.
        var settled: Bool
        var note: String?
        /// On a book's barcode row: the recognizer's second language for a bilingual book
        /// ("fr-FR"), beside the reader's own (ux-notes row 126).
        var languages: [String]?

        var testDescription: String { "\(slug)/\(file)" }
    }

    static let manifestName = "private-pages"

    /// Whether the manifest lists the book at all. A book folder with no entries yet (photos
    /// delivered for a later slice) is left out of the strict checks and named in the report.
    static func isInManifest(_ book: Book) -> Bool {
        manifest.contains { $0.slug == book.slug }
    }

    static let manifest: [Entry] = {
        guard let url = Bundle.module.url(forResource: manifestName, withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }()
}
