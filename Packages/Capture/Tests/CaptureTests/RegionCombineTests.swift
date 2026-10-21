import Foundation
import Testing
@testable import Capture

/// Scan review's Combine (ux-notes row 88): regions joined as the page prints them. The text is made
/// up; the shapes are Nobu's end notes (a label, the phrase beside it, the rest) and a step broken by
/// a shadow.
@Suite("Combining regions")
struct RegionCombineTests {
    @Test func aLabelAndTheNoteBesideItReadAsOneLine() {
        let combined = PageRegionText.combined([
            (PageRect(x: 0.10, y: 0.80, width: 0.05, height: 0.012), ["NOTE"]),
            (PageRect(x: 0.16, y: 0.80, width: 0.22, height: 0.012), ["The broth keeps for"]),
            // The rest starts on the same printed line and wraps back to the margin.
            (PageRect(x: 0.10, y: 0.80, width: 0.62, height: 0.036), ["two days, covered,", "in the refrigerator; warm it", "gently before serving."]),
        ])
        #expect(combined.lines == ["NOTE The broth keeps for two days, covered,", "in the refrigerator; warm it", "gently before serving."])
        #expect(abs(combined.rect.minX - 0.10) < 1e-9 && abs(combined.rect.maxX - 0.72) < 1e-9 && abs(combined.rect.maxY - 0.836) < 1e-9)
        #expect(PageRegionText.paragraph(combined.lines) == "NOTE The broth keeps for two days, covered, in the refrigerator; warm it gently before serving.")
    }

    @Test func piecesOnLinesOfTheirOwnStackInOrder() {
        // A step a shadow split across the page: its three pieces, one under another.
        let combined = PageRegionText.combined([
            (PageRect(x: 0.10, y: 0.40, width: 0.60, height: 0.024), ["Simmer the beans until tender,", "about 40 minutes. Drain, re-"]),
            (PageRect(x: 0.10, y: 0.425, width: 0.60, height: 0.012), ["serving a cup of the liquid,"]),
            (PageRect(x: 0.10, y: 0.438, width: 0.40, height: 0.012), ["and season well."]),
        ])
        #expect(combined.lines.count == 4)
        #expect(PageRegionText.paragraph(combined.lines) == "Simmer the beans until tender, about 40 minutes. Drain, reserving a cup of the liquid, and season well.")
    }

    @Test func aLabelTheReaderListedAfterItsParagraphStillLeads() {
        // The paragraph's box holds the label's line, from the same margin.
        let combined = PageRegionText.combined([
            (PageRect(x: 0.100, y: 0.600, width: 0.40, height: 0.048), ["The broth keeps for two days,", "covered, in the refrigerator;", "warm it gently before", "serving."]),
            (PageRect(x: 0.101, y: 0.604, width: 0.04, height: 0.012), ["note"]),
        ])
        #expect(combined.lines.first == "note The broth keeps for two days,")
        #expect(combined.lines.count == 4)
    }

    @Test func twoPiecesOfOneLineReadLeftToRight() {
        // The reader listed the right half first.
        let combined = PageRegionText.combined([
            (PageRect(x: 0.40, y: 0.20, width: 0.25, height: 0.012), ["with Charred Scallions"]),
            (PageRect(x: 0.10, y: 0.20, width: 0.28, height: 0.012), ["Grilled Flatbread"]),
        ])
        #expect(combined.lines == ["Grilled Flatbread with Charred Scallions"])
    }
}
