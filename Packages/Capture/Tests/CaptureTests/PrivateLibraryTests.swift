import Foundation
import Testing
@testable import Capture

/// Caleb's own Paprika or Mela export, when one is saved under `Docs/Fixtures/Private` (gitignored):
/// every recipe in it must read, with a title and at least one ingredient or step. Counts are
/// recorded in Docs/Specs/phase1-notes.md, never recipe text. Skipped when no export is present.
@Suite("Library import, private export", .enabled(if: !Fixtures.privateLibraries.isEmpty, "No Paprika or Mela export under Docs/Fixtures/Private"))
struct PrivateLibraryTests {
    @Test("Every recipe reads", arguments: Fixtures.privateLibraries)
    func everyRecipeReads(_ file: URL) throws {
        let library = try LibraryArchive(data: Data(contentsOf: file), fileName: file.lastPathComponent)
        #expect(library.count > 0)
        var unreadable: [String] = []
        var empty = 0
        for index in 0..<library.count {
            guard let recipe = try? library.recipe(at: index) else {
                unreadable.append(library.name(at: index))
                continue
            }
            if recipe.ingredients.isEmpty && recipe.steps.isEmpty { empty += 1 }
        }
        #expect(unreadable.isEmpty, "Unreadable: \(unreadable)")
        print("\(file.lastPathComponent): \(library.format.appName), \(library.count) recipes, \(empty) without ingredients or steps")
    }
}
