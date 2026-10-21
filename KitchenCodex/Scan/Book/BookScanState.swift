import Capture
import Foundation

/// A whole-book session's own state (03 §3.8, 02 Flow C steps 4–6), kept as JSON in the book's
/// scan folder beside the captures, so Close pauses with nothing lost and a relaunch picks the
/// queue up where it stopped. The punchlist's progress is the entries' statuses, in the library;
/// this holds what the library has no place for: the current item, the courses the cook chose per
/// chapter (no schema change is available, so the saved recipes carry them), the layouts the
/// session has seen, the captures not yet let go, and the entries page pointers put on the list
/// (a reference pointer's entry is what slice 7 captures as a `Reference`).
///
/// Every key is read if present, so a field added later leaves an older file readable (the Oct 21
/// review's finding 12).
struct BookScanState: Codable {
    /// The punchlist's current item (`BookEntry.id`).
    var currentEntry: UUID?
    /// The course the cook chose for a chapter (`BookSection.id`), "" for none.
    var courses: [UUID: String] = [:]
    /// Layout signatures of recipes the session saved: a recipe of a layout already in the review
    /// queue doesn't need to be there too (04 §5.1 "Scan review": the first recipe of a layout
    /// confirms it).
    var layouts: [String] = []
    var captures: [StoredCapture] = []
    var nextCaptureID = 0
    /// Bumped each time the session opens.
    var sitting = 0
    /// Pages the book's recipes point to that went on its to-scan list (04 §5.1 "Page pointers").
    var pointerEntries: [PointerEntry] = []

    /// One capture: the cleaned page in the folder, what the camera noted, and what it became.
    struct StoredCapture: Codable, Identifiable {
        enum Status: String, Codable {
            /// Waiting for the queue.
            case pending
            /// Read, and saved as what it is.
            case processed
            /// It couldn't be read.
            case failed
        }

        let id: Int
        /// The file in the scan folder.
        let file: String
        var mode: CaptureMode
        var quality: Quality?
        /// "Page 3 · Sharp".
        var note: String
        /// The punchlist's current item when it was captured: a page with no page number is that
        /// entry. Nil for photos chosen in a batch, which take the current item as each is read.
        var entry: UUID?
        /// Needs review as the cook set it on the last capture's pane; nil when untouched.
        var flagged: Bool?
        var status: Status = .pending
        /// The recipes saved from it (`Recipe.id`).
        var recipes: [UUID] = []
        /// A Photo capture's image on its recipe (`RecipeImage.id`).
        var photo: UUID?
        var pageNumber: Int?
        /// The pages its recipes point a photograph to ("photograph on page 12").
        var photographPages: [Int] = []
        /// Its recipes are in the review queue.
        var queued = false
        /// What became of it, for the captures sheet.
        var detail: String?
        /// A page that continued the capture before it was read into that capture's recipe.
        var joinedTo: Int?
        /// The sitting it was taken in, so a later sitting's counts start afresh.
        var sitting: Int = 0
        /// Entries made for its recipes because the list lacked them (`BookEntry.id`), taken back
        /// with the capture (the Oct 21 review's finding 8).
        var createdEntries: [UUID] = []
        /// Its recipes that are a page shot again over a recipe the cook reviewed or edited: both
        /// kept until the captures sheet's Keep Earlier · Keep New is answered (ux-notes row 93).
        var duplicates: [Duplicate] = []

        init(id: Int, file: String, mode: CaptureMode, quality: Quality?, note: String) {
            self.id = id
            self.file = file
            self.mode = mode
            self.quality = quality
            self.note = note
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            file = try container.decode(String.self, forKey: .file)
            mode = try container.decodeIfPresent(CaptureMode.self, forKey: .mode) ?? .recipe
            quality = try container.decodeIfPresent(Quality.self, forKey: .quality)
            note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
            entry = try container.decodeIfPresent(UUID.self, forKey: .entry)
            flagged = try container.decodeIfPresent(Bool.self, forKey: .flagged)
            status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .pending
            recipes = try container.decodeIfPresent([UUID].self, forKey: .recipes) ?? []
            photo = try container.decodeIfPresent(UUID.self, forKey: .photo)
            pageNumber = try container.decodeIfPresent(Int.self, forKey: .pageNumber)
            photographPages = try container.decodeIfPresent([Int].self, forKey: .photographPages) ?? []
            queued = try container.decodeIfPresent(Bool.self, forKey: .queued) ?? false
            detail = try container.decodeIfPresent(String.self, forKey: .detail)
            joinedTo = try container.decodeIfPresent(Int.self, forKey: .joinedTo)
            sitting = try container.decodeIfPresent(Int.self, forKey: .sitting) ?? 0
            createdEntries = try container.decodeIfPresent([UUID].self, forKey: .createdEntries) ?? []
            duplicates = try container.decodeIfPresent([Duplicate].self, forKey: .duplicates) ?? []
        }
    }

    /// A recipe saved from a page already captured, beside the earlier one it would replace.
    struct Duplicate: Codable, Equatable {
        /// The recipe saved from this capture (`Recipe.id`).
        var new: UUID
        /// The recipe already on the entry.
        var earlier: UUID
        /// The entry both are of (`BookEntry.id`).
        var entry: UUID
    }

    /// A page a recipe points to, put on the to-scan list (or found on it) by the cross-reference
    /// card or the session's rule: the entry, the page, whether it reads as reference material
    /// rather than a recipe, and the recipes pointing there, which link to the recipe once it is
    /// captured (or, for a reference, which slice 7 links to the `Reference` as related reading).
    struct PointerEntry: Codable, Equatable {
        var entry: UUID
        var page: Int
        var isReference: Bool
        /// The pointer as printed ("see page 253").
        var phrase: String
        /// `PageCrossReference.Kind` raw value.
        var kind: String
        var recipes: [UUID]
        /// The pointer made the entry (rather than finding it on the contents list), so it goes
        /// once no recipe points there and nothing was captured.
        var madeEntry: Bool
    }

    /// The gate's reading of a capture before cleanup.
    struct Quality: Codable {
        var quality: String
        var sharpness: Double
        var smudge: Double

        init(_ reading: PageQualityReading) {
            quality = reading.quality.rawValue
            sharpness = reading.sharpness
            smudge = reading.smudge
        }

        var reading: PageQualityReading? {
            PageQuality(rawValue: quality).map { PageQualityReading(quality: $0, sharpness: sharpness, smudge: smudge) }
        }
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentEntry = try container.decodeIfPresent(UUID.self, forKey: .currentEntry)
        courses = try container.decodeIfPresent([UUID: String].self, forKey: .courses) ?? [:]
        layouts = try container.decodeIfPresent([String].self, forKey: .layouts) ?? []
        captures = try container.decodeIfPresent([StoredCapture].self, forKey: .captures) ?? []
        nextCaptureID = try container.decodeIfPresent(Int.self, forKey: .nextCaptureID) ?? (captures.map(\.id).max() ?? -1) + 1
        sitting = try container.decodeIfPresent(Int.self, forKey: .sitting) ?? 0
        pointerEntries = try container.decodeIfPresent([PointerEntry].self, forKey: .pointerEntries) ?? []
    }
}

extension BookScanState {
    /// Where a book's session keeps its state and captures: Application Support, so nothing there
    /// is backed up twice or shown in Files.
    static func folder(for bookID: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "Book Scans/\(bookID.uuidString)", directoryHint: .isDirectory)
    }

    static func load(bookID: UUID) -> BookScanState? {
        let url = folder(for: bookID).appending(path: "session.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BookScanState.self, from: data)
    }

    func save(bookID: UUID) {
        let folder = Self.folder(for: bookID)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: folder.appending(path: "session.json"), options: .atomic)
    }

    /// Books whose sessions left captures waiting, for a relaunch to resume and the background task
    /// to drain (ux-notes row 92).
    static func booksWithPendingCaptures() -> [UUID] {
        let root = URL.applicationSupportDirectory.appending(path: "Book Scans", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap(UUID.init(uuidString:)).filter { id in
            load(bookID: id)?.captures.contains { $0.status == .pending } == true
        }
    }
}
