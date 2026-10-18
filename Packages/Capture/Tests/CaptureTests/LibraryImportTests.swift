import Foundation
import Testing
@testable import Capture

/// Paprika and Mela exports, built in the test from synthetic recipes.
@Suite("Library import")
struct LibraryImportTests {
    /// 1×1 PNG.
    static let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    static var roastChicken: [String: Any] { [
        "uid": "A1", "name": "Roast Chicken",
        "ingredients": "1 whole chicken (4 lb)\n2 tsp kosher salt\nFor the pan sauce:\n1 cup chicken stock\n2 tbsp butter",
        "directions": "Salt the chicken a day ahead.\n\nRoast at 425°F until the thigh reads 165°F, about 1 hour.\n\nDO AHEAD: Salt up to 2 days ahead.\n\nMake the pan sauce with the stock and butter.",
        "notes": "Use a cast-iron pan.", "description": "Our Sunday standby.",
        "servings": "Servings: 4", "prep_time": "15 mins", "cook_time": "1 hr 10 mins", "total_time": "",
        "source": "Test Kitchen", "source_url": "https://example.test/roast-chicken",
        "image_url": "https://example.test/chicken.jpg", "photo_data": pixel,
        "categories": ["Weeknight", "Dinner"], "rating": 5, "on_favorites": 1, "created": "2021-03-14 18:22:05",
    ] }

    static var salad: [String: Any] { [
        "name": "Green Salad", "ingredients": "1 head lettuce\n2 tbsp vinaigrette",
        "directions": "Wash the lettuce.\nToss with the vinaigrette.", "servings": "", "categories": [],
        "on_favorites": 0, "source": "", "source_url": "", "notes": "",
    ] }

    static func paprikaEntry(_ recipe: [String: Any]) throws -> Data {
        try TestArchives.gzip(JSONSerialization.data(withJSONObject: recipe))
    }

    @Test func readsAPaprikaArchive() throws {
        let archive = try TestArchives.zip([
            ("Roast Chicken.paprikarecipe", try Self.paprikaEntry(Self.roastChicken), true),
            ("Green Salad.paprikarecipe", try Self.paprikaEntry(Self.salad), false),
            ("__MACOSX/._Green Salad.paprikarecipe", Data([0, 1, 2]), false),
        ])
        let library = try LibraryArchive(data: archive, fileName: "My Recipes.paprikarecipes")
        #expect(library.format == .paprika)
        #expect(library.count == 2)

        let chicken = try library.recipe(at: 0)
        #expect(chicken.title == "Roast Chicken")
        #expect(chicken.ingredients == ["1 whole chicken (4 lb)", "2 tsp kosher salt", "1 cup chicken stock", "2 tbsp butter"])
        #expect(chicken.ingredientGroups == [2: "For the pan sauce"])
        #expect(chicken.steps.map(\.text) == [
            "Salt the chicken a day ahead.",
            "Roast at 425°F until the thigh reads 165°F, about 1 hour.",
            "Make the pan sauce with the stock and butter.",
        ])
        #expect(chicken.notes == ["Use a cast-iron pan.", "DO AHEAD: Salt up to 2 days ahead."])
        #expect(chicken.headnote == "Our Sunday standby.")
        #expect(chicken.yield == "4")
        #expect(chicken.servings == 4)
        #expect(chicken.prepTime == .seconds(15 * 60))
        #expect(chicken.cookTime == .seconds(70 * 60))
        #expect(chicken.totalTime == nil)
        #expect(chicken.siteName == "Test Kitchen")
        #expect(chicken.sourceURL?.absoluteString == "https://example.test/roast-chicken")
        #expect(chicken.imageURL?.absoluteString == "https://example.test/chicken.jpg")
        #expect(chicken.imageData == Data(base64Encoded: Self.pixel))
        #expect(chicken.category == "Weeknight, Dinner")
        #expect(chicken.isFavorite)
        #expect(chicken.createdAt != nil)
        #expect(chicken.method == .libraryFile)
        #expect(chicken.importedFrom == "Paprika")
        #expect(!chicken.needsReview)

        let salad = try library.recipe(at: 1)
        #expect(salad.steps.map(\.text) == ["Wash the lettuce.", "Toss with the vinaigrette."])
        #expect(salad.yield == nil)
        #expect(salad.category == nil)
        #expect(salad.sourceURL == nil)
        #expect(salad.siteName == nil)
        #expect(!salad.isFavorite)
        #expect(salad.notes.isEmpty)
    }

    @Test func readsASinglePaprikaRecipe() throws {
        let library = try LibraryArchive(data: try Self.paprikaEntry(Self.salad), fileName: "Green Salad.paprikarecipe")
        #expect(library.format == .paprika)
        #expect(library.count == 1)
        #expect(try library.recipe(at: 0).title == "Green Salad")
    }

    @Test func reportsADamagedEntryAndKeepsTheRest() throws {
        let archive = try TestArchives.zip([
            ("Broken.paprikarecipe", Data("not gzip, not json".utf8), false),
            ("Green Salad.paprikarecipe", try Self.paprikaEntry(Self.salad), true),
        ])
        let library = try LibraryArchive(data: archive, fileName: "export.paprikarecipes")
        #expect(throws: LibraryImportError.unreadable("Broken.paprikarecipe")) { try library.recipe(at: 0) }
        #expect(try library.recipe(at: 1).title == "Green Salad")
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: (any Error).self) { try LibraryArchive(data: Data("hello".utf8), fileName: "notes.txt") }
    }

    static var melaBread: [String: Any] { [
        "id": "m1", "title": "Country Bread", "text": "A weekend loaf.",
        "ingredients": "# Levain\n50 g starter\n50 g flour\n# Dough\n450 g flour\n350 g water\n10 g salt",
        "instructions": "# Day 1\nFeed the starter.\nMix the levain.\n# Day 2\nMix the dough and fold every 30 minutes.\nTip: Wet your hands.\nBake at 475°F.",
        "notes": "Rye flour works too.", "yield": "1 loaf", "prepTime": "30 min", "cookTime": "45 min", "totalTime": "24 h",
        "link": "https://example.test/bread", "images": [pixel], "categories": ["Bread", "Baking"], "favorite": true,
        "date": 700_000_000.0,
    ] }

    @Test func readsAMelaRecipe() throws {
        let library = try LibraryArchive(data: try JSONSerialization.data(withJSONObject: Self.melaBread), fileName: "Country Bread.melarecipe")
        #expect(library.format == .mela)
        let bread = try library.recipe(at: 0)
        #expect(bread.title == "Country Bread")
        #expect(bread.ingredients == ["50 g starter", "50 g flour", "450 g flour", "350 g water", "10 g salt"])
        #expect(bread.ingredientGroups == [0: "Levain", 2: "Dough"])
        #expect(bread.steps.map(\.text) == ["Feed the starter.", "Mix the levain.", "Mix the dough and fold every 30 minutes.", "Bake at 475°F."])
        #expect(bread.notes == ["Rye flour works too.", "Tip: Wet your hands."])
        #expect(bread.headnote == "A weekend loaf.")
        #expect(bread.yield == "1 loaf")
        #expect(bread.totalTime == .seconds(24 * 3600))
        #expect(bread.sourceURL?.absoluteString == "https://example.test/bread")
        #expect(bread.imageData == Data(base64Encoded: Self.pixel))
        #expect(bread.category == "Bread, Baking")
        #expect(bread.isFavorite)
        #expect(bread.createdAt == Date(timeIntervalSinceReferenceDate: 700_000_000))
        #expect(bread.importedFrom == "Mela")
    }

    @Test func readsAMelaArchiveWithABookAsItsLink() throws {
        var fromBook = Self.melaBread
        fromBook["title"] = "Focaccia"
        fromBook["link"] = "Flour Water Salt Yeast, p. 180"
        fromBook["favorite"] = false
        let archive = try TestArchives.zip([
            ("Country Bread.melarecipe", try JSONSerialization.data(withJSONObject: Self.melaBread), true),
            ("Focaccia.melarecipe", try JSONSerialization.data(withJSONObject: fromBook), false),
        ])
        let library = try LibraryArchive(data: archive, fileName: "Recipes.melarecipes")
        #expect(library.format == .mela)
        #expect(library.count == 2)
        let focaccia = try library.recipe(at: 1)
        #expect(focaccia.sourceURL == nil)
        #expect(focaccia.siteName == "Flour Water Salt Yeast, p. 180")
        #expect(!focaccia.isFavorite)
    }

    @Test func sniffsTheFormatWhenTheExtensionIsMissing() throws {
        let archive = try TestArchives.zip([("Bread.melarecipe", try JSONSerialization.data(withJSONObject: Self.melaBread), true)])
        #expect(try LibraryArchive(data: archive, fileName: "download.zip").format == .mela)
    }
}

/// Minimal ZIP and gzip writers for building test archives.
enum TestArchives {
    /// `(name, contents, deflate)` entries.
    static func zip(_ entries: [(String, Data, Bool)]) throws -> Data {
        var archive = Data()
        var directory = Data()
        for (name, contents, deflate) in entries {
            let stored = deflate ? try (contents as NSData).compressed(using: .zlib) as Data : contents
            let nameBytes = Data(name.utf8)
            let crc = crc32(contents)
            let offset = UInt32(archive.count)
            archive.append(le32(0x0403_4B50)); archive.append(le16(20)); archive.append(le16(0x0800))
            archive.append(le16(deflate ? 8 : 0)); archive.append(le32(0))
            archive.append(le32(crc)); archive.append(le32(UInt32(stored.count))); archive.append(le32(UInt32(contents.count)))
            archive.append(le16(UInt16(nameBytes.count))); archive.append(le16(0))
            archive.append(nameBytes); archive.append(stored)

            directory.append(le32(0x0201_4B50)); directory.append(le16(20)); directory.append(le16(20)); directory.append(le16(0x0800))
            directory.append(le16(deflate ? 8 : 0)); directory.append(le32(0))
            directory.append(le32(crc)); directory.append(le32(UInt32(stored.count))); directory.append(le32(UInt32(contents.count)))
            directory.append(le16(UInt16(nameBytes.count))); directory.append(le16(0)); directory.append(le16(0))
            directory.append(le16(0)); directory.append(le16(0)); directory.append(le32(0)); directory.append(le32(offset))
            directory.append(nameBytes)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(le32(0x0605_4B50)); archive.append(le16(0)); archive.append(le16(0))
        archive.append(le16(UInt16(entries.count))); archive.append(le16(UInt16(entries.count)))
        archive.append(le32(UInt32(directory.count))); archive.append(le32(directoryOffset)); archive.append(le16(0))
        return archive
    }

    static func gzip(_ data: Data) throws -> Data {
        var result = Data([0x1F, 0x8B, 8, 0x08, 0, 0, 0, 0, 0, 3])
        result.append(Data("recipe.json".utf8)); result.append(0)
        result.append(try (data as NSData).compressed(using: .zlib) as Data)
        result.append(le32(crc32(data))); result.append(le32(UInt32(data.count)))
        return result
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }

    private static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
}
