import Foundation
import Testing
@testable import Capture

/// A book's Sources page into suppliers (02 Flow C step 8, 03 §3.17 Sources). The page is made up.
@Suite("Sources page")
struct SourcesPageReaderTests {
    @Test func readsSuppliersUnderTheirGroups() throws {
        let sources = SourcesPageReader.read(lines: [
            "SOURCES",
            "EQUIPMENT",
            "Harbor Kitchen Supply",
            "412 Front Street, Portland, ME 04101",
            "(207) 555-0143 · www.harborkitchensupply.com",
            "Copper pots, lidded terrine molds and the wide shallow pans the braises want.",
            "Northline Restaurant Hardware",
            "northlinehardware.com",
            "Sheet pans, hotel pans and a good scale.",
            "FOOD",
            "Two Rivers Farm",
            "Box 9, Starks, ME 04911",
            "207-555-0199",
            "Lamb, eggs and the first asparagus of the year; they ship to the Northeast.",
            "Sakura Pantry",
            "www.sakurapantry.com",
            "Kombu, bonito flakes, yuzu kosho and the rice we use for everything.",
            "DRINK",
            "Cellar & Co.",
            "88 Water Street, Portland, ME 04101",
            "(207) 555-0170",
            "Sake, vermouth and bitters.",
        ])
        #expect(sources.map(\.name) == ["Harbor Kitchen Supply", "Northline Restaurant Hardware", "Two Rivers Farm", "Sakura Pantry", "Cellar & Co."])
        #expect(sources.map(\.categories) == [["equipment"], ["equipment"], ["food"], ["food"], ["drink"]])
        #expect(sources.map(\.kind) == [.store, .online, .producer, .online, .store])
        let harbor = sources[0]
        #expect(harbor.address == "412 Front Street, Portland, ME 04101")
        #expect(harbor.phone == "(207) 555-0143")
        #expect(harbor.url?.absoluteString == "https://www.harborkitchensupply.com")
        #expect(harbor.carries == "Copper pots, lidded terrine molds and the wide shallow pans the braises want.")
        #expect(sources[1].url?.absoluteString == "https://northlinehardware.com")
        #expect(sources[2].address == "Box 9, Starks, ME 04911")
        #expect(sources[2].phone == "207-555-0199")
        #expect(sources[4].carries == "Sake, vermouth and bitters.")
    }

    @Test func readsNamesPrintedAfterWhatTheyCarry() {
        // Name, then what they carry, then the contact: the next name starts the next entry.
        let sources = SourcesPageReader.read(lines: [
            "Resources",
            "Harbor Kitchen Supply",
            "Copper pots and molds.",
            "(207) 555-0143",
            "Two Rivers Farm",
            "Lamb and eggs.",
            "207-555-0199",
        ])
        #expect(sources.map(\.name) == ["Harbor Kitchen Supply", "Two Rivers Farm"])
        #expect(sources.map(\.carries) == ["Copper pots and molds.", "Lamb and eggs."])
        #expect(sources.map(\.phone) == ["(207) 555-0143", "207-555-0199"])
        #expect(sources.map(\.categories) == [[], []])
    }

    @Test func readsSmallCapsNamesOverTwoLinesAndSpelledNumbers() {
        // Headings with an introduction under them, names in capitals set over two lines, numbers
        // spelled in letters, a contact line.
        let sources = SourcesPageReader.read(lines: [
            "SOURCES",
            "FOR EQUIPMENT",
            "Equipment used in this book can be found at one of the following.",
            "HARBOR KITCHEN",
            "SUPPLY COMPANY",
            "866-PANSHOP (72674671)",
            "www.harborkitchen.com",
            "copper pots and molds",
            "FOR FOOD",
            "Most good food stores carry these.",
            "TWO RIVERS FARM",
            "Contact: Pat Example",
            "207-555-0199",
            "lamb and eggs",
        ])
        #expect(sources.map(\.name) == ["HARBOR KITCHEN SUPPLY COMPANY", "TWO RIVERS FARM"])
        #expect(sources.map(\.categories) == [["equipment"], ["food"]])
        #expect(sources[0].phone == "866-PANSHOP (72674671)")
        #expect(sources[1].carries == "lamb and eggs")
    }

    @Test func tellsTheLinesApart() {
        #expect(SourcesPageReader.isName("Harbor Kitchen Supply"))
        #expect(SourcesPageReader.isName("CELLAR & CO."))
        #expect(!SourcesPageReader.isName("Copper pots and the wide shallow pans"))
        #expect(!SourcesPageReader.isName("412 Front Street"))
        #expect(SourcesPageReader.isAddress("412 Front Street"))
        #expect(SourcesPageReader.isAddress("Portland, ME 04101"))
        #expect(SourcesPageReader.isAddress("P.O. Box 12"))
        #expect(!SourcesPageReader.isAddress("Sake, vermouth and bitters."))
        #expect(SourcesPageReader.phoneNumber(in: "Tel: (207) 555-0143") == "(207) 555-0143")
        #expect(SourcesPageReader.website(in: "Online at harborkitchensupply.com.")?.absoluteString == "https://harborkitchensupply.com")
        #expect(SourcesPageReader.categoryHeading("Japanese Ingredients") == "food")
        #expect(SourcesPageReader.categoryHeading("Harbor Kitchen Supply") == nil)
    }
}
