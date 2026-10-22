import Foundation
import Testing
@testable import Capture

/// Page pointers in a recipe's text (04 §5.1 "Page pointers", ux-notes row 74): what the pill
/// covers, the pages, and what the words say the page holds. The lines are made up.
@Suite("Page pointers")
struct PagePointerTests {
    @Test func coversTheWordsThatPointAndKeepsTheRest() throws {
        let line = "2 cups Broth (see page 17)"
        let pointer = try #require(PagePointers.find(in: line).first)
        #expect(pointer.text == "see page 17")
        #expect(String(line[pointer.range]) == "see page 17")
        #expect(pointer.pages == [17])
        #expect(pointer.kind == .recipe)
        #expect(pointer.target == "Broth")
    }

    @Test func readsWhatThePointerSaysThePageHolds() {
        let text = "1 cup dried kelp (kombu, see page 253), salt (see Sources, page 301), and truss the bird (see page 88 for a quicker method). Herb Butter (page 214) or see pages 31 and 97."
        let pointers = PagePointers.find(in: text)
        #expect(pointers.map(\.text) == ["see page 253", "page 301", "see page 88", "page 214", "see pages 31 and 97"])
        #expect(pointers.map(\.kind) == [.recipe, .sources, .technique, .recipe, .recipe])
        #expect(pointers.map(\.pages) == [[253], [301], [88], [214], [31, 97]])
        // A lowercase name before the parentheses names nothing; the book's list decides what p. 253 is.
        #expect(pointers.map(\.target) == [nil, nil, nil, "Herb Butter", nil])
    }

    /// ux-notes row 102: the to-scan entry's title from the pointer.
    @Test func titlesTheEntryFromTheNameInTheParenthesesElseTheItem() throws {
        let kelp = try #require(PagePointers.find(in: "1 4-inch piece of dried kelp (kombu, see page 253)").first)
        #expect(kelp.name == "kombu")
        #expect(kelp.entryTitle(item: "4-inch piece of dried kelp") == "Kombu")
        let plain = try #require(PagePointers.find(in: "1 4-inch piece of dried kelp (see page 253)").first)
        #expect(plain.name == nil)
        #expect(plain.entryTitle(item: "4-inch piece of dried kelp") == "Dried kelp")
        #expect(plain.entryTitle(item: "2 large onions, sliced") == "Onions, sliced")
        #expect(plain.entryTitle(item: nil) == "Page 253")
        // A capitalized name before the parentheses still comes first.
        let butter = try #require(PagePointers.find(in: "2 tablespoons Herb Butter (page 214)").first)
        #expect(butter.entryTitle(item: "Herb Butter") == "Herb Butter")
        // "or Broth" names broth; a Sources pointer names nothing.
        #expect(PagePointers.find(in: "2 cups water (or Broth, see page 17)").first?.name == "Broth")
        #expect(PagePointers.find(in: "salt (see Sources, page 301)").first?.name == nil)
        #expect(PagePointers.itemName("one 3-pound chicken") == "chicken")
    }

    /// ux-notes row 132: the words a glossary entry may be headed by, in the order to try them.
    @Test func triesTheTargetTheItemThenTheNameInTheParentheses() throws {
        let kelp = try #require(PagePointers.find(in: "1 4-inch piece of kombu (dried kelp, see page 253)").first)
        #expect(kelp.termCandidates(item: "4-inch piece of kombu") == ["kombu", "dried kelp"])
        let butter = try #require(PagePointers.find(in: "2 tablespoons Herb Butter (page 214)").first)
        #expect(butter.termCandidates(item: "Herb Butter") == ["Herb Butter"])
        // In a step there is no ingredient line: the target, then the parentheses.
        let step = try #require(PagePointers.find(in: "Brush with the glaze (honey glaze, see page 40).").first)
        #expect(step.termCandidates() == ["honey glaze"])
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
