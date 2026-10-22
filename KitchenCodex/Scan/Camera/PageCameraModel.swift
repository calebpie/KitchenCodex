import AVFoundation
import Capture
import Observation
import RecipeModel
import UIKit

/// The camera's state (03 §3.5): the live outline and quality pill, the capture mode, the torch and
/// auto-capture, the captured pages, and the barcode seen at the start. Each capture is measured by
/// the gate, cleaned (`PageCleanup`) and handed to its sink (Scan Page's session or the whole-book
/// session), whose queue reads it while the cook carries on.
@MainActor
@Observable
final class PageCameraModel {
    struct Thumbnail: Identifiable {
        let id: Int
        let image: UIImage
        var mode: CaptureMode
    }

    let session: any PageCaptureSink
    let controller = CameraController()

    /// Recipe · Photo (ux-notes rows 62 and 82): Recipe is the resting mode, and a Photo capture is
    /// one capture, the switch going back to Recipe after it.
    var mode = CaptureMode.recipe
    /// The torch, off by default (ux-notes row 85): lit continuously while on.
    var flash = false {
        didSet { if flash != oldValue { controller.setTorch(flash) } }
    }
    /// Capture whenever a page is held steady in view. Remembered between sessions.
    var autoCapture: Bool {
        didSet { UserDefaults.standard.set(autoCapture, forKey: Self.autoCaptureKey) }
    }
    /// The outline drawn over the viewfinder: Vision's, steadied (ux-notes row 133).
    private(set) var outline: PageQuad?
    /// What to change when no page has been found for two seconds; the pill shows it.
    private(set) var hint: PageOutlineSmoother.Hint?
    /// The frame's width over its height, as shown, for drawing the outline.
    private(set) var frameAspect: CGFloat = 3 / 4
    /// The gate's reading of a live frame, about once a second; advisory only.
    private(set) var liveQuality: PageQuality?
    private(set) var isRunning = false
    private(set) var failure: String?
    private(set) var thumbnails: [Thumbnail] = []
    /// Captures still being cleaned.
    private(set) var preparing = 0
    /// "Page 3 · Sharp", shown for a moment after a capture.
    private(set) var captureNote: String?
    /// Bumped on each capture, for the shutter's blink and the haptic.
    private(set) var shutterCount = 0
    /// The book the barcode at the start named, or the ISBN of a new one.
    private(set) var scannedTitle: String?

    private var addChain: Task<Void, Never>?
    private var isAssessing = false
    private var smoother = PageOutlineSmoother()
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    // Auto-capture: when the page in view has held still, and whether it changed since the last capture.
    private var lastQuad: PageQuad?
    private var steadySince: ContinuousClock.Instant?
    private var missingSince: ContinuousClock.Instant?
    private var capturedQuad: PageQuad?
    private var pageChanged = true

    private static let autoCaptureKey = "camera.autoCapture"
    /// A held page moves less than this (a share of the frame) from one look to the next.
    static let steadyDistance = 0.012
    /// How long a page is held before auto-capture takes it.
    static let steadyTime = Duration.milliseconds(700)
    /// A page smaller than this share of the frame is not taken automatically.
    static let autoCaptureArea = 0.2

    init(session: any PageCaptureSink) {
        self.session = session
        autoCapture = UserDefaults.standard.object(forKey: Self.autoCaptureKey) as? Bool ?? false
    }

    var pageCount: Int { thumbnails.count }

    // MARK: - Session

    func start() async {
        controller.onOutline = { [weak self] quad, aspect, luminance in
            Task { @MainActor in self?.handleOutline(quad, aspect: aspect, luminance: luminance) }
        }
        controller.onQualityFrame = { [weak self] frame in
            Task { @MainActor in self?.assess(frame) }
        }
        controller.onISBN = { [weak self] isbn in
            Task { @MainActor in self?.handleISBN(isbn) }
        }
        do {
            try await controller.start()
            isRunning = true
            if !session.namesBookByBarcode { controller.setReadsBarcodes(false) }
            if flash { controller.setTorch(true) }
            if let previewLayer { attach(previewLayer) }
        } catch {
            failure = "The camera couldn't start. Close and try again, or choose photos instead."
        }
    }

    func stop() {
        controller.stop()
        isRunning = false
    }

    /// The preview's layer, once it exists: the rotation coordinator keeps frames and captures level.
    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        guard rotation == nil, isRunning, let device = controller.captureDevice else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        rotation = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor in self?.applyPreviewAngle(angle) }
        }
    }

    private func applyPreviewAngle(_ angle: CGFloat) {
        if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        controller.setFrameAngle(angle)
    }

    // MARK: - Live frames

    /// The outline, steadied, with its hint, and auto-capture: a page held still for a moment is
    /// taken when auto-capture is on and the page changed since the last capture (it left the view
    /// or moved, as when a page is turned). Auto-capture reads Vision's outline as it comes.
    private func handleOutline(_ quad: PageQuad?, aspect: CGFloat, luminance: Double?) {
        frameAspect = aspect
        let now = ContinuousClock.now
        outline = smoother.feed(quad, at: now, aspect: Double(aspect), luminance: luminance)
        hint = smoother.hint(at: now)
        guard let quad, quad.area() >= Self.autoCaptureArea else {
            steadySince = nil
            lastQuad = nil
            if capturedQuad != nil {
                let since = missingSince ?? now
                missingSince = since
                if now - since >= .milliseconds(400) { pageChanged = true }
            }
            return
        }
        missingSince = nil
        if let capturedQuad, quad.distance(to: capturedQuad) > 0.12 { pageChanged = true }
        if let lastQuad, quad.distance(to: lastQuad) < Self.steadyDistance {
            if steadySince == nil { steadySince = now }
        } else {
            steadySince = nil
        }
        lastQuad = quad
        if autoCapture, pageChanged, let since = steadySince, now - since >= Self.steadyTime, preparing == 0 {
            steadySince = nil
            shutter()
        }
    }

    /// The pill: the gate over a live frame, one at a time.
    private func assess(_ frame: CGImage) {
        guard !isAssessing else { return }
        isAssessing = true
        Task {
            let reading = await Self.assess(frame)
            liveQuality = reading.quality
            isAssessing = false
        }
    }

    @concurrent
    nonisolated private static func assess(_ frame: CGImage) async -> PageQualityReading {
        await PageQualityGate().assess(frame)
    }

    /// The barcode shown before the first page names the book (ux-notes row 65).
    private func handleISBN(_ isbn: String) {
        guard session.namesBookByBarcode, thumbnails.isEmpty, preparing == 0, session.scannedISBN != isbn else { return }
        session.scannedISBN = isbn
        if let book = session.shelfBook(isbn: isbn) {
            scannedTitle = book.displayTitle
        } else {
            scannedTitle = "New cookbook · ISBN \(isbn)"
        }
    }

    func clearScannedBook() {
        session.scannedISBN = nil
        scannedTitle = nil
    }

    // MARK: - Capturing

    /// Takes a photo now. Never blocked by the pill (ux-notes row 57).
    func shutter() {
        guard isRunning, preparing < 3 else { return }
        if thumbnails.isEmpty, preparing == 0 { controller.setReadsBarcodes(false) }
        capturedQuad = lastQuad ?? outline
        pageChanged = false
        shutterCount += 1
        let index = session.reserveCaptureID()
        preparing += 1
        let mode = mode
        // Photo is one capture (ux-notes row 82).
        if mode == .photo { self.mode = .recipe }
        let angle = rotation?.videoRotationAngleForHorizonLevelCapture ?? 90
        let folder = session.captureFolder()
        let controller = controller
        let work = Task { () -> Prepared? in
            guard let data = try? await controller.capture(angle: angle) else { return nil }
            return await Self.prepare(data, mode: mode, folder: folder, index: index)
        }
        // Into the queue in capture order, whichever cleanup finishes first.
        let previous = addChain
        addChain = Task {
            let prepared = await work.value
            await previous?.value
            preparing -= 1
            guard let prepared else {
                captureNote = "That capture didn't come through. Try again."
                return
            }
            thumbnails.append(Thumbnail(id: index, image: UIImage(cgImage: prepared.thumbnail), mode: mode))
            let label = mode == .photo ? "Photo" : "Page"
            let note = prepared.quality.map { "\(label) \(thumbnails.count) · \($0.quality.label)" } ?? "\(label) \(thumbnails.count)"
            session.addCapture(id: index, at: prepared.url, mode: mode, quality: prepared.quality, note: note)
            captureNote = note
            try? await Task.sleep(for: .seconds(2))
            if captureNote == note { captureNote = nil }
        }
    }

    // MARK: - The captures sheet

    /// Deletes a capture from the stack, the queue and the scan (ux-notes row 83).
    func removeCapture(id: Int) {
        thumbnails.removeAll { $0.id == id }
        session.removeCapture(id: id)
    }

    /// A capture made a recipe page or a photo after the fact.
    func setMode(_ mode: CaptureMode, ofCapture id: Int) {
        if let index = thumbnails.firstIndex(where: { $0.id == id }) { thumbnails[index].mode = mode }
        session.setMode(mode, ofCapture: id)
    }

    struct Prepared: Sendable {
        let url: URL
        let quality: PageQualityReading?
        let thumbnail: CGImage
    }

    /// One capture made ready: upright at full size, measured by the gate before anything changes
    /// it (sharpening would flatter a soft photo), the page found and cleaned, written as the file
    /// the pipeline reads and the page scan is stored from. The original photo is not kept.
    @concurrent
    nonisolated static func prepare(_ data: Data, mode: CaptureMode, folder: URL, index: Int) async -> Prepared? {
        guard let image = try? PageImage.load(data: data) else { return nil }
        let quality = mode == .recipe ? await PageQualityGate().assess(image) : nil
        let page = await PageCleanup.detectPage(in: image)
        guard let cleaned = PageCleanup.clean(image, page: page, enhances: mode == .recipe && PageCleanup.enhancesPages),
              let file = PageCleanup.encoded(cleaned) else { return nil }
        let url = folder.appending(path: "capture-\(index + 1).\(file.fileExtension)")
        guard (try? file.data.write(to: url)) != nil else { return nil }
        let thumbnail = (try? PageImage.load(data: file.data, maxPixelSize: 240)) ?? cleaned
        return Prepared(url: url, quality: quality, thumbnail: thumbnail)
    }
}
