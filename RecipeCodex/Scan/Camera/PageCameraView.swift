import AVFoundation
import Capture
import SwiftUI

/// Scan Page's camera (03 §3.5, 02 Flow B steps 1–3), a full-screen cover: the viewfinder with the
/// live page outline, the quality pill at the top, Close, the flash and auto-capture toggles and
/// Done; at the bottom the shutter, the Recipe · Photo mode beside it, Add Next Page once a page
/// exists and the captured pages stacking at the left with their count. On iPad the camera sits
/// beside a running preview of the last capture's text. Controls are clear glass over the
/// viewfinder, with a dim layer at the top and bottom. Never shown in the Simulator.
struct PageCameraView: View {
    /// Done: the captures go on to the processing sheet.
    var onDone: () -> Void
    /// Close: the captures are discarded.
    var onClose: () -> Void

    @Bindable var session: ScanSession
    @State private var camera: PageCameraModel
    @State private var isConfirmingClose = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(session: ScanSession, onDone: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.session = session
        self.onDone = onDone
        self.onClose = onClose
        _camera = State(initialValue: PageCameraModel(session: session))
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                viewfinder
                if sizeClass == .regular, geometry.size.width > 900 {
                    CaptureTextPreview(session: session, pageCount: camera.pageCount)
                        .frame(width: min(420, geometry.size.width * 0.34))
                }
            }
        }
        .background(.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .sensoryFeedback(.impact(weight: .light), trigger: camera.shutterCount)
        .sensoryFeedback(.success, trigger: camera.scannedTitle)
        // Only a run of hazy, poorly read captures asks (ux-notes row 57); the shutter never waits.
        .alert("Clean the Lens?", isPresented: $session.asksToCleanLens) {
            Button("Continue Anyway", role: .cancel) {}
            Button("Done Cleaning") {}
        } message: {
            Text("The last three pages looked hazy and read poorly. Wipe the camera lens with a soft cloth, then carry on.")
        }
        .confirmationDialog(camera.pageCount == 1 ? "Discard the page?" : "Discard \(camera.pageCount) pages?", isPresented: $isConfirmingClose, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: onClose)
            Button("Keep Scanning", role: .cancel) {}
        }
    }

    // MARK: - The viewfinder

    private var viewfinder: some View {
        ZStack {
            CameraPreview(session: camera.controller.session) { camera.attach($0) }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            PageOutline(quad: camera.outline, frameAspect: camera.frameAspect)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.12), value: camera.outline)
            // The shutter's blink.
            Color.white
                .opacity(0)
                .ignoresSafeArea()
                .phaseAnimator([0.0, 0.5, 0.0], trigger: camera.shutterCount) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in .easeOut(duration: 0.12) }
                .allowsHitTesting(false)
            // A dim layer behind the controls, for legibility over any page.
            VStack {
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom).frame(height: 160)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom).frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                topBar
                statusLine
                Spacer()
                if let failure = camera.failure {
                    Text(failure)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .glassEffect(in: .rect(cornerRadius: 16))
                        .padding(.horizontal)
                }
                if let note = camera.captureNote {
                    Text(note)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect()
                        .transition(.opacity)
                }
                bottomBar
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .animation(.default, value: camera.captureNote)
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("Close", systemImage: "xmark") {
                if camera.pageCount > 0 { isConfirmingClose = true } else { onClose() }
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .frame(width: 44, height: 44)
            .glassEffect(.clear.interactive(), in: .circle)
            .keyboardShortcut(.cancelAction)

            Spacer()

            GlassEffectContainer {
                HStack(spacing: 4) {
                    Toggle(isOn: $camera.flash) {
                        Label("Flash", systemImage: camera.flash ? "bolt.fill" : "bolt.slash")
                    }
                    Toggle(isOn: $camera.autoCapture) {
                        Label("Auto-Capture", systemImage: camera.autoCapture ? "a.circle.fill" : "a.circle")
                    }
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 44)
                .glassEffect(.clear.interactive(), in: .capsule)
            }

            Spacer()

            Button("Done") { onDone() }
                .font(.headline)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                .disabled(camera.pageCount == 0 || camera.preparing > 0)
                .opacity(camera.pageCount == 0 ? 0 : 1)
        }
        .foregroundStyle(.white)
    }

    /// The quality pill (advisory: it never stops the shutter), and the book the barcode named.
    private var statusLine: some View {
        VStack(spacing: 8) {
            if let quality = camera.liveQuality {
                QualityPill(quality: quality)
            }
            if let title = camera.scannedTitle {
                HStack(spacing: 8) {
                    Image(systemName: "barcode")
                    Text(title)
                        .lineLimit(1)
                    Button("Not This Book", systemImage: "xmark.circle.fill") { camera.clearScannedBook() }
                        .labelStyle(.iconOnly)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.clear, in: .capsule)
            } else if camera.pageCount == 0, camera.isRunning, session.startingBook == nil {
                Text("Show the barcode on the back cover to name the book, or start with a page.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .animation(.default, value: camera.liveQuality)
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 14) {
            // Recipe · Photo, sticky (ux-notes row 62): what the next capture is.
            Picker("Capture", selection: $camera.mode) {
                Text("Recipe").tag(ScanSession.CaptureMode.recipe)
                Text("Photo").tag(ScanSession.CaptureMode.photo)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .accessibilityHint("Recipe pages are read; a photo goes with the recipe as a cover.")

            // Fixed slots either side keep the shutter centred before the first page, when Add
            // Next Page isn't there yet.
            HStack {
                CaptureStack(thumbnails: camera.thumbnails)
                    .frame(width: 88, alignment: .leading)
                Spacer()
                shutter
                Spacer()
                ZStack(alignment: .trailing) { addNextPage }
                    .frame(width: 88, alignment: .trailing)
            }
        }
    }

    private var shutter: some View {
        Button {
            camera.shutter()
        } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                Circle().fill(camera.mode == .photo ? Color.yellow : Color.white).frame(width: 62, height: 62)
            }
        }
        .buttonStyle(.plain)
        .disabled(!camera.isRunning || camera.preparing >= 3)
        .accessibilityLabel(camera.mode == .photo ? "Capture Photo" : "Capture Page")
        .keyboardShortcut(.space, modifiers: [])
    }

    @ViewBuilder
    private var addNextPage: some View {
        if camera.pageCount > 0 {
            Button {
                camera.addNextPage()
            } label: {
                VStack(spacing: 4) {
                    if camera.isAwaitingNextPage {
                        ProgressView().tint(.white)
                        Text("Hold Steady")
                    } else {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.title3)
                        Text("Add Next Page")
                    }
                }
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .frame(width: 84, height: 64)
                .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityHint(camera.isAwaitingNextPage ? "Waiting for the page to be held steady. Tap to stop waiting." : "Turn the page; it is captured as soon as it's held steady.")
        }
    }
}

/// The pill's three readings (02 Flow B step 2): Sharp in green, Hold still and Clean the lens in
/// amber.
private struct QualityPill: View {
    let quality: PageQuality

    var body: some View {
        Label(quality.label, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(quality == .sharp ? Color.green : Color.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.clear, in: .capsule)
            .accessibilityLabel("Quality: \(quality.label)")
    }

    private var symbol: String {
        switch quality {
        case .sharp: "checkmark.circle.fill"
        case .holdStill: "hand.raised.fill"
        case .cleanTheLens: "camera.aperture"
        }
    }
}

/// The captured pages stacking at the bottom left with their count.
private struct CaptureStack: View {
    let thumbnails: [PageCameraModel.Thumbnail]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                ForEach(Array(thumbnails.suffix(3).enumerated()), id: \.element.id) { offset, thumbnail in
                    Image(uiImage: thumbnail.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 64)
                        .clipShape(.rect(cornerRadius: 4))
                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(thumbnail.mode == .photo ? Color.yellow : Color.white, lineWidth: 1.5) }
                        .rotationEffect(.degrees(Double(offset - min(2, thumbnails.count - 1)) * 6))
                        .offset(x: CGFloat(offset) * 3)
                }
            }
            if !thumbnails.isEmpty {
                Text("\(thumbnails.count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(.white, in: .capsule)
                    .offset(x: 10, y: -10)
            }
        }
        .frame(width: 64, height: 76)
        .animation(.spring(duration: 0.3), value: thumbnails.count)
        .accessibilityElement()
        .accessibilityLabel(thumbnails.count == 1 ? "1 page captured" : "\(thumbnails.count) pages captured")
    }
}

/// The page's outline over the viewfinder: the frame filled into the view as the preview fills it.
private struct PageOutline: View {
    let quad: PageQuad?
    let frameAspect: CGFloat

    var body: some View {
        GeometryReader { geometry in
            if let quad {
                let points = quad.corners.map { Self.place($0, in: geometry.size, frameAspect: frameAspect) }
                Path { path in
                    path.addLines(points)
                    path.closeSubpath()
                }
                .fill(Color.accentColor.opacity(0.16))
                .overlay {
                    Path { path in
                        path.addLines(points)
                        path.closeSubpath()
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                }
            }
        }
    }

    /// A unit point of the frame, where the aspect-filled preview shows it.
    static func place(_ point: PagePoint, in size: CGSize, frameAspect: CGFloat) -> CGPoint {
        guard size.width > 0, size.height > 0, frameAspect > 0 else { return .zero }
        var width = size.width, height = size.height
        if frameAspect > size.width / size.height {
            width = height * frameAspect
        } else {
            height = width / frameAspect
        }
        return CGPoint(x: (size.width - width) / 2 + point.x * width, y: (size.height - height) / 2 + point.y * height)
    }
}

/// iPad: the last capture's text as it is read, so a bad capture shows before the next page.
private struct CaptureTextPreview: View {
    let session: ScanSession
    let pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(pageCount == 0 ? "No pages yet" : "Last capture")
                    .font(.headline)
                Spacer()
                if session.isReadingCaptures {
                    ProgressView()
                    Text("Reading…")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            Divider()
            ScrollView {
                Text(session.lastCaptureText ?? (pageCount == 0 ? "Capture a page and its text appears here as it's read." : ""))
                    .font(.callout)
                    .foregroundStyle(session.lastCaptureText == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
        }
        .background(.background)
        .environment(\.colorScheme, .dark)
    }
}

/// The capture session's preview layer.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onLayer: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        let layer = view.previewLayer
        Task { @MainActor in onLayer(layer) }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
