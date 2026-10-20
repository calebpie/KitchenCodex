import Foundation

/// The regions of one scanned page as scan review shows them (03 §3.6), stored as JSON in
/// `RecipeImage.regions`: each block the reader found, where it sits on the page, what it says, how
/// sure the reader was, and what the structurer made of it. Review recolors and reassigns regions,
/// and an item in the structured recipe flashes its source region through `item`.
///
/// Rects are in unit page coordinates with the origin at the top left of the image as shown
/// (orientation applied): x and y from 0 to 1 across and down, so they survive any scaling of the
/// stored image.
public struct ScanRegions: Codable, Sendable, Equatable {
    /// The format of this JSON; 1 since Phase 2 slice 2.
    public var version: Int
    /// The page's layout signature (`Book.reviewedLayouts` holds the ones the cook confirmed).
    public var layoutSignature: String?
    /// The page number read off the page (a folio or running head), when there was one.
    public var pageNumber: Int?
    public var regions: [ScanRegion]

    public init(version: Int = 1, layoutSignature: String? = nil, pageNumber: Int? = nil, regions: [ScanRegion] = []) {
        self.version = version
        self.layoutSignature = layoutSignature
        self.pageNumber = pageNumber
        self.regions = regions
    }

    /// The JSON for `RecipeImage.regions`.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Reads `RecipeImage.regions`; nil when there is nothing stored or it can't be read.
    public static func decoded(from data: Data?) -> ScanRegions? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ScanRegions.self, from: data)
    }
}

/// One block on a scanned page.
public struct ScanRegion: Codable, Sendable, Equatable {
    /// What the reader saw: "heading", "paragraph", "line", "list", "table", "photo" (Capture's
    /// `PageBlock.Kind` raw values).
    public var kind: String
    /// What the block is in the recipe: "title", "yield", "time", "headnote", "ingredient",
    /// "ingredientGroup", "step", "note", "stepPhoto", "furniture", "crossReference", "ignore", or
    /// nil while unassigned (Capture's `PageBlock.Role` raw values). Review sets it when the cook
    /// reassigns a region.
    public var role: String?
    /// x, y, width, height in unit page coordinates, top-left origin.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var text: String
    /// The reader's confidence, 0…1.
    public var confidence: Double
    /// The index of the structured item the region became (the ingredient line, the step), when it
    /// became one.
    public var item: Int?

    public init(kind: String, role: String? = nil, x: Double, y: Double, width: Double, height: Double, text: String = "", confidence: Double = 0, item: Int? = nil) {
        self.kind = kind
        self.role = role
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.text = text
        self.confidence = confidence
        self.item = item
    }
}
