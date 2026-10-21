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
    /// with a page number. Counts only, never a title.
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
        /// False where the counts are the reading's and could not be checked against the page.
        var settled: Bool
        var note: String?

        var testDescription: String { "\(slug)/\(file)" }
    }

    static let manifestName = "private-pages"

    static let manifest: [Entry] = {
        guard let url = Bundle.module.url(forResource: manifestName, withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }()
}
