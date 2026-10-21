import AVFoundation
import Capture
import CoreImage
import ImageIO
import OSLog
import Synchronization
import UIKit
import Vision

/// Whether Scan Page can offer its camera, and asking for access on first use (03 §3.5).
enum CameraAccess {
    /// A camera to use and the usage description the system asks with. Never in the Simulator,
    /// which has no camera, so nothing there presents one.
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else { return false }
        return AVCaptureDevice.default(for: .video) != nil
        #endif
    }

    /// The cook turned camera access off (or it is restricted), so Settings is the way back.
    static var isDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    /// Access, asked for the first time it is needed.
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

/// The capture session behind Scan Page's camera (03 §3.5, 02 Flow B steps 1–3): the back camera
/// (the Pro's virtual camera, so a close page gets the macro lens), a photo output at about 24
/// megapixels as the fixtures were shot, video frames for the live page outline (Vision's document
/// segmentation, about ten a second) and the quality pill (the gate, about once a second), and
/// EAN-13 metadata for an ISBN barcode shown at the start. Everything AVFoundation touches runs on
/// the session queue or the video queue; results go back through the callbacks.
nonisolated final class CameraController: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    /// The page outline in a frame, in unit coordinates of the frame as shown, and the frame's
    /// width over its height.
    var onOutline: (@Sendable (PageQuad?, CGFloat) -> Void)?
    /// A frame for the quality pill, about once a second.
    var onQualityFrame: (@Sendable (CGImage) -> Void)?
    /// An ISBN read off a barcode in view (on the main queue).
    var onISBN: (@Sendable (String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.calebpietrafesa.KitchenCodex.camera.session")
    private let videoQueue = DispatchQueue(label: "com.calebpietrafesa.KitchenCodex.camera.video", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var device: AVCaptureDevice?
    private var isConfigured = false

    /// The camera in use, once the session is set up (for the rotation coordinator).
    var captureDevice: AVCaptureDevice? { device }
    /// Captures in flight, kept until their photo arrives.
    private let delegates = Mutex<[Int64: PhotoDelegate]>([:])

    // The video queue's own state.
    private var lastOutline = ContinuousClock.now - .seconds(1)
    private var lastQualityFrame = ContinuousClock.now
    /// The angle frames are delivered at when the connection can't turn them (Vision turns them).
    private let frameAngle = Mutex<CGFloat>(90)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static let logger = Logger(subsystem: "com.calebpietrafesa.KitchenCodex", category: "camera")

    enum CameraError: Error {
        case noCamera
        case cannotConfigure
        case noPhoto
    }

    // MARK: - Session

    /// Sets the session up once and starts it.
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    if !isConfigured { try configure() }
                    if !session.isRunning { session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() throws {
        let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let device else { throw CameraError.noCamera }
        self.device = device
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else { throw CameraError.cannotConfigure }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        // About 24 megapixels, as the phone's own camera shoots and the fixtures were shot: the
        // reader is tuned there, and 48 would double the reading time.
        let sizes = device.activeFormat.supportedMaxPhotoDimensions
        let area = { (size: CMVideoDimensions) in Int(size.width) * Int(size.height) }
        if let size = sizes.filter({ area($0) <= 25_000_000 }).max(by: { area($0) < area($1) }) ?? sizes.min(by: { area($0) < area($1) }) {
            photoOutput.maxPhotoDimensions = size
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            if metadataOutput.availableMetadataObjectTypes.contains(.ean13) {
                metadataOutput.metadataObjectTypes = [.ean13]
            }
        }

        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }
        isConfigured = true
    }

    /// The angle frames are turned to so they match the preview, from the rotation coordinator.
    func setFrameAngle(_ angle: CGFloat) {
        sessionQueue.async { [self] in
            guard let connection = videoOutput.connection(with: .video) else { return }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
                frameAngle.withLock { $0 = 0 }
            } else {
                frameAngle.withLock { $0 = angle }
            }
        }
    }

    /// Stops looking for barcodes once the first page is in (the barcode is the session's opening).
    func setReadsBarcodes(_ reads: Bool) {
        sessionQueue.async { [self] in
            let types: [AVMetadataObject.ObjectType] = reads && metadataOutput.availableMetadataObjectTypes.contains(.ean13) ? [.ean13] : []
            metadataOutput.metadataObjectTypes = types
        }
    }

    /// Flash as a continuous torch (04 §5.1 "Camera controls", ux-notes row 85): lit while the cook
    /// has it on, so glare on a glossy page shows in the preview before the capture; no flash is
    /// fired on capture. A stopped session puts the torch out, so the camera sets it again on start.
    func setTorch(_ on: Bool) {
        sessionQueue.async { [self] in
            guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            let mode: AVCaptureDevice.TorchMode = on ? .on : .off
            if device.isTorchModeSupported(mode), device.torchMode != mode { device.torchMode = mode }
        }
    }

    // MARK: - Capturing

    /// One photo, HEIC where the phone takes it, with its orientation in its metadata: `angle` is
    /// the rotation coordinator's horizon-level capture angle. Never with the flash: the torch, when
    /// the cook turned it on, is the light.
    func capture(angle: CGFloat) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            sessionQueue.async { [self] in
                let settings = photoOutput.availablePhotoCodecTypes.contains(.hevc)
                    ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    : AVCapturePhotoSettings()
                settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
                settings.photoQualityPrioritization = .quality
                if photoOutput.supportedFlashModes.contains(.off) { settings.flashMode = .off }
                if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                let id = settings.uniqueID
                let delegate = PhotoDelegate { [weak self] result in
                    _ = self?.delegates.withLock { $0.removeValue(forKey: id) }
                    continuation.resume(with: result)
                }
                delegates.withLock { $0[id] = delegate }
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    nonisolated private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
        private let completion: (Result<Data, Error>) -> Void
        /// Answered once: the photo, or the capture's failure if no photo came.
        private let isDone = Mutex(false)

        init(completion: @escaping (Result<Data, Error>) -> Void) {
            self.completion = completion
        }

        private func finish(_ result: Result<Data, Error>) {
            guard !isDone.withLock({ done in defer { done = true }; return done }) else { return }
            completion(result)
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            if let error {
                finish(.failure(error))
            } else if let data = photo.fileDataRepresentation() {
                finish(.success(data))
            } else {
                finish(.failure(CameraError.noPhoto))
            }
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
            finish(.failure(error ?? CameraError.noPhoto))
        }
    }
}

// MARK: - Frames

nonisolated extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ContinuousClock.now
        let angle = frameAngle.withLock { $0 }
        let orientation = Self.orientation(forAngle: angle)
        let width = CGFloat(CVPixelBufferGetWidth(pixels)), height = CGFloat(CVPixelBufferGetHeight(pixels))
        let turned = angle == 90 || angle == 270
        let aspect = turned ? height / width : width / height

        // The page outline, about ten times a second.
        if now - lastOutline >= .milliseconds(100) {
            lastOutline = now
            let request = VNDetectDocumentSegmentationRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation)
            var quad: PageQuad?
            if (try? handler.perform([request])) != nil, let page = request.results?.first {
                func point(_ p: CGPoint) -> PagePoint { PagePoint(x: p.x, y: 1 - p.y) }
                quad = PageQuad(topLeft: point(page.topLeft), topRight: point(page.topRight),
                                bottomRight: point(page.bottomRight), bottomLeft: point(page.bottomLeft))
            }
            onOutline?(quad.flatMap { $0.isConvex ? $0 : nil }, aspect)
        }

        // A frame for the quality pill, about once a second, at a size the gate measures quickly.
        if now - lastQualityFrame >= .seconds(1), let onQualityFrame {
            lastQualityFrame = now
            var image = CIImage(cvPixelBuffer: pixels).oriented(orientation)
            let scale = min(1, 1_600 / max(image.extent.width, image.extent.height))
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            if let frame = ciContext.createCGImage(image, from: image.extent.integral) {
                onQualityFrame(frame)
            }
        }
    }

    private static func orientation(forAngle angle: CGFloat) -> CGImagePropertyOrientation {
        switch Int(angle) {
        case 90: .right
        case 180: .down
        case 270: .left
        default: .up
        }
    }
}

// MARK: - Barcodes

nonisolated extension CameraController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        for case let code as AVMetadataMachineReadableCodeObject in metadataObjects {
            if let value = code.stringValue, let isbn = ISBN.normalized(value) {
                onISBN?(isbn)
                return
            }
        }
    }
}
