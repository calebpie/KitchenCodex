import Foundation
import Testing

/// Loads the hand-written fixtures in this test target and the private saved pages, which live
/// outside the package in `Docs/Fixtures/Private/HTML` and are not in the public repository.
enum Fixtures {
    static func synthetic(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Synthetic") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    static func syntheticData(_ name: String) throws -> Data {
        Data(try synthetic(name).utf8)
    }

    // MARK: - Private pages

    /// `Docs/Fixtures/Private/HTML`, found by walking up from this file to the repository root.
    /// Nil in CI and cloud checkouts, where the copyrighted pages are absent.
    static let privateDirectory: URL? = {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appending(path: "Docs/Fixtures/Private/HTML")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }()

    static var privatePagesAvailable: Bool { privateDirectory != nil }

    static let privateSkipReason: Comment = "Docs/Fixtures/Private/HTML is not in this checkout (the saved pages are copyrighted and gitignored)"

    static func privatePageNames() -> [String] {
        guard let directory = privateDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { $0.hasSuffix(".html") }.sorted()
    }

    static func privatePage(_ name: String) throws -> String {
        guard let directory = privateDirectory else { throw CocoaError(.fileNoSuchFile) }
        return String(decoding: try Data(contentsOf: directory.appending(path: name)), as: UTF8.self)
    }

    // MARK: - Expectations

    /// What each private page should import as: titles and counts only, never page text.
    struct Expectation: Codable, Sendable, CustomTestStringConvertible {
        var file: String
        var title: String?
        var ingredients: Int
        var steps: Int
        /// Ingredient group headings, steps with a source photo, and asides moved to notes.
        var groups: Int?
        var stepImages: Int?
        var notes: Int?
        /// `ImportMethod` raw value, or nil when the page should yield no recipe.
        var method: String?
        var note: String?

        var testDescription: String { file }
    }

    static let expectations: [Expectation] = {
        guard let url = Bundle.module.url(forResource: "private-fixtures", withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Expectation].self, from: data)) ?? []
    }()
}
