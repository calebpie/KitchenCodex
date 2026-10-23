import Capture
import Foundation
import Observation
import RecipeModel
import SwiftUI

/// What a capture is (04 §5.1 "Printed photos", "Camera controls"; ux-notes rows 62 and 82): a
/// recipe page to read, or a photo (a plate, the finished dish) for a recipe read in the session.
/// Recipe is the resting mode; a Photo capture is one capture.
enum CaptureMode: String, Codable {
    case recipe, photo
}

/// One capture as the captures sheet lists it (ux-notes row 83).
struct CaptureItem: Identifiable, Equatable {
    let id: Int
    let url: URL
    var mode: CaptureMode
    /// "Page 3 · Sharp", as the camera noted it.
    var note: String
    /// What became of it, once read: "Saved: Leek Soup", "A cover for Leek Soup".
    var detail: String?
    /// The book session's Needs Review for the capture, shown as a pill (ux-notes row 135); nil
    /// where there is no review queue.
    var needsReview: Bool?
    /// A page shot again over a recipe the cook reviewed or edited (ux-notes row 93): the question,
    /// answered Keep Earlier · Keep New.
    var keepWhich: String?
    /// A page continuing a recipe the cook reviewed or edited since (ux-notes row 100): the
    /// question, answered Join · Keep Apart.
    var joinWhich: String?
    /// A contents page shot in the book session (ux-notes row 114): the word, answered Add to the
    /// Recipe List · Retake.
    var contentsWhich: String?
}

/// One text block of the last capture, for the iPad's running preview (03 §3.5, ux-notes row 87):
/// every block the reader found, ignored ones and the page's furniture dimmed.
struct CapturePreviewBlock: Identifiable, Equatable {
    let id: Int
    let text: String
    let isDimmed: Bool
}

extension PageReading {
    /// Every text block in reading order, photos left out; what nothing claimed, the ignored and the
    /// running heads and folios dimmed.
    var previewBlocks: [CapturePreviewBlock] {
        blocks.filter { $0.kind != .photo && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.map { block in
            CapturePreviewBlock(id: block.id, text: block.text, isDimmed: block.role == nil || block.role == .ignore || block.role == .furniture)
        }
    }
}

/// Where the camera's captures go (03 §3.5, §3.8): Scan Page's session, or the whole-book
/// session. The camera hands each cleaned capture over with an id the sink gave it, and the
/// captures sheet deletes one or changes its designation through it.
@MainActor
protocol PageCaptureSink: AnyObject, Observable {
    /// Whether a barcode shown before the first page names the book: Scan Page started from no
    /// book. The book session knows its book.
    var namesBookByBarcode: Bool { get }
    /// The barcode read live at the camera's start.
    var scannedISBN: String? { get set }
    /// A run of hazy, poorly read captures asks to clean the lens (ux-notes row 57).
    var asksToCleanLens: Bool { get set }
    var lastCapturePreview: [CapturePreviewBlock] { get }
    /// Whether a capture is still being read.
    var isReadingCaptures: Bool { get }
    var captureItems: [CaptureItem] { get }
    /// What the camera's ✕ asks before discarding, when the sink says more than the page count
    /// (the book session: the sitting's captures and the recipes saved from them).
    var discardQuestion: (title: String, message: String?)? { get }

    /// The folder the camera writes its cleaned pages to.
    func captureFolder() -> URL
    /// A fresh id for the next capture.
    func reserveCaptureID() -> Int
    func addCapture(id: Int, at url: URL, mode: CaptureMode, quality: PageQualityReading?, note: String)
    /// Deleting a capture removes it from the queue and the scan.
    func removeCapture(id: Int)
    func setMode(_ mode: CaptureMode, ofCapture id: Int)
    /// Keep Earlier · Keep New for a page shot again (the book session).
    func resolveDuplicates(of id: Int, keepNew: Bool)
    /// Join · Keep Apart for a page continuing a reviewed recipe (the book session).
    func resolveJoin(of id: Int, join: Bool)
    /// Add to the Recipe List · Retake for a contents page shot in the book session.
    func resolveContents(of id: Int, add: Bool)
    /// The shelf's book with this ISBN.
    func shelfBook(isbn: String) -> Book?
}

extension PageCaptureSink {
    var discardQuestion: (title: String, message: String?)? { nil }
    func resolveDuplicates(of id: Int, keepNew: Bool) {}
    func resolveJoin(of id: Int, join: Bool) {}
    func resolveContents(of id: Int, add: Bool) {}
}

/// Three captures in a row hazy and poorly read (ux-notes row 57): Clean the lens stays advisory
/// until both Apple's smudge threshold and a poor reading come three times running.
struct LensWatch {
    private var hazyRun = 0

    /// Notes a Recipe capture's reading; true when it is time to ask.
    mutating func note(_ reading: PageReading, quality: PageQualityReading?) -> Bool {
        let hazy = (quality?.smudge ?? 0) >= PageQualityGate().smudgeThreshold && reading.ocrConfidence < PageStructurer.lowOCR
        hazyRun = hazy ? hazyRun + 1 : 0
        guard hazyRun >= 3 else { return false }
        hazyRun = 0
        return true
    }

    mutating func reset() { hazyRun = 0 }
}

/// The camera's captures in order (ux-notes row 83, 04 §5.1 "Camera controls"): each with its
/// thumbnail, its note and what became of it, a Recipe/Photo switch, a Needs Review pill when the
/// app flagged it, swipe to delete.
struct CaptureListSheet: View {
    let items: [CaptureItem]
    /// Each capture's Recipe/Photo switch: hidden where every capture is a page (ux-notes row 116).
    var showsMode = true
    var onDelete: (Int) -> Void
    var onSetMode: (Int, CaptureMode) -> Void
    /// Keep Earlier (false) · Keep New (true) for a page shot again.
    var onKeep: ((Int, Bool) -> Void)?
    /// Join (true) · Keep Apart (false) for a page continuing a reviewed recipe (row 100).
    var onJoin: ((Int, Bool) -> Void)?
    /// Add to the Recipe List (true) · Retake (false) for a contents page (row 114).
    var onContents: ((Int, Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("No captures yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(items) { item in
                    CaptureRow(item: item, showsMode: showsMode) { onSetMode(item.id, $0) } onKeep: { onKeep?(item.id, $0) } onJoin: { onJoin?(item.id, $0) } onContents: { onContents?(item.id, $0) }
                }
                .onDelete { offsets in
                    for id in offsets.map({ items[$0].id }) { onDelete(id) }
                }
            }
            .navigationTitle(items.count == 1 ? "1 Capture" : "\(items.count) Captures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CaptureRow: View {
    let item: CaptureItem
    var showsMode: Bool
    var onSetMode: (CaptureMode) -> Void
    var onKeep: (Bool) -> Void
    var onJoin: (Bool) -> Void
    var onContents: (Bool) -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Color(.secondarySystemFill)
                }
            }
            .frame(width: 48, height: 64)
            .clipShape(.rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(item.mode == .photo ? Color.yellow : Color(.separator), lineWidth: item.mode == .photo ? 1.5 : 0.5) }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                // The app's own flag in the title's row (ux-notes rows 135, 157): a warning pill
                // after a spacer, never a toggle, and never over the title.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.note)
                        .font(.headline)
                    Spacer(minLength: 0)
                    if item.needsReview == true { NeedsReviewPill() }
                }
                if let detail = item.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if showsMode {
                    Picker("Capture", selection: Binding { item.mode } set: { onSetMode($0) }) {
                        Text("Recipe").tag(CaptureMode.recipe)
                        Text("Photo").tag(CaptureMode.photo)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
                if let question = item.keepWhich {
                    // Until the cook answers, both copies stay (ux-notes row 93).
                    Text(question)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Keep Earlier") { onKeep(false) }
                        Button("Keep New") { onKeep(true) }
                    }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                }
                if let word = item.contentsWhich {
                    // Nothing is saved from it until the cook answers (ux-notes row 114).
                    Text(word)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Add to the Recipe List") { onContents(true) }
                        Button("Retake") { onContents(false) }
                    }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                }
                if let question = item.joinWhich {
                    // The page stays on its own until the cook answers (ux-notes row 100).
                    Text(question)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Join") { onJoin(true) }
                        Button("Keep Apart") { onJoin(false) }
                    }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .task(id: item.url) { thumbnail = await Self.thumbnail(item.url).map(UIImage.init(cgImage:)) }
    }

    @concurrent
    nonisolated private static func thumbnail(_ url: URL) async -> CGImage? {
        try? PageImage.load(contentsOf: url, maxPixelSize: 200)
    }
}

/// The app's Needs Review flag on a capture (ux-notes row 135): a warning pill, never a toggle.
struct NeedsReviewPill: View {
    var body: some View {
        Label("Needs Review", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.15), in: .capsule)
    }
}
