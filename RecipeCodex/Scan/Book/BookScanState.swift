import Capture
import Foundation

/// A whole-book session's own state (03 §3.8, 02 Flow C steps 4–6), kept as JSON in the book's
/// scan folder beside the captures, so Close pauses with nothing lost and a relaunch picks the
/// queue up where it stopped. The punchlist's progress is the entries' statuses, in the library;
/// this holds what the library has no place for: the current item, the courses the cook chose per
/// chapter (no schema change is available, so the saved recipes carry them), the layouts the
/// session has seen, and the captures not yet let go.
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

    /// Bumped each time the session opens.
    var sitting = 0
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

    /// Books whose sessions left captures waiting, for a relaunch to resume (and, later, a
    /// background task to drive).
    static func booksWithPendingCaptures() -> [UUID] {
        let root = URL.applicationSupportDirectory.appending(path: "Book Scans", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.compactMap(UUID.init(uuidString:)).filter { id in
            load(bookID: id)?.captures.contains { $0.status == .pending } == true
        }
    }
}
