import Foundation
import Testing
@testable import Capture

/// Page pointers in a recipe's text (04 §5.1 "Page pointers", ux-notes row 74): what the pill
/// covers, the pages, and what the words say the page holds. The lines are made up.
@Suite("Page pointers")
struct PagePointerTests {
    @Test func coversTheWordsThatPointAndKeepsTheRest() throws {
        let line = "2 cups Dashi (see page 17)"
        let pointer = try #require(PagePointers.find(in: line).first)
        #expect(pointer.text == "see page 17")
        #expect(String(line[pointer.range]) == "see page 17")
        #expect(pointer.pages == [17])
        #expect(pointer.kind == .recipe)
        #expect(pointer.target == "Dashi")
    }

    @Test func readsWhatThePointerSaysThePageHolds() {
        let text = "1 cup mountain yam (yama-imo, see page 253), salt (see Sources, page 301), and truss the bird (see page 88 for a quicker method). Herb Butter (page 214) or see pages 31 and 97."
        let pointers = PagePointers.find(in: text)
        #expect(pointers.map(\.text) == ["see page 253", "page 301", "see page 88", "page 214", "see pages 31 and 97"])
        #expect(pointers.map(\.kind) == [.recipe, .sources, .technique, .recipe, .recipe])
        #expect(pointers.map(\.pages) == [[253], [301], [88], [214], [31, 97]])
        // A lowercase name before the parentheses names nothing; the book's list decides what p. 253 is.
        #expect(pointers.map(\.target) == [nil, nil, nil, "Herb Butter", nil])
    }

    @Test func leavesPhotographPointersOut() {
        #expect(PagePointers.find(in: "PHOTOGRAPH ON PAGE 6").isEmpty)
        #expect(PagePointers.find(in: "Photographs on pages 31 and 97").isEmpty)
        #expect(PagePointers.find(in: "Turn to the next page and keep going.").isEmpty)
    }

    @Test func findsARecipeThatFollows() throws {
        let reference = try #require(PageCrossReferences.find(in: "1/2 cup Garlic Aioli (recipe follows)", kind: .recipe).first)
        #expect(reference.kind == .recipe)
        #expect(reference.pages.isEmpty)
        #expect(reference.target == "Garlic Aioli")
    }
}
