import AVFoundation
import Capture
import SwiftUI

/// The camera (03 §3.5, 02 Flow B steps 1–3), Scan Page's full-screen cover and the whole-book
/// session's camera page (03 §3.8): the viewfinder full bleed with the live page outline, the
/// quality pill at the top (what to change when no page can be found, ux-notes row 133), ✕ and
/// Done in matching slots either side of Flash and Auto, two round glass buttons with their
/// captions (row 140); at the bottom the shutter, the Recipe · Photo mode above it, the captured
/// pages stacking at the left with their count, which opens the captures to look over, and on the
/// right what the page that shows the camera puts there (the session's four figures, row 134).
/// Add Next Page is gone: Auto covers it. On iPad Scan Page's camera sits beside a running preview
/// of the last capture's text. Controls are clear glass over the viewfinder, with a dim layer at
/// the top and bottom. Never shown in the Simulator.
struct PageCameraView: View {
    /// Done: Scan Page's captures go on to the processing sheet; the book session saves and closes.
    var onDone: () -> Void
    /// ✕: the captures are discarded, after the sink's question (or "Discard N pages?").
    var onClose: () -> Void
    /// Whether ✕ asks before discarding the pages.
    var confirmsClose = true
    /// The iPad's running text preview beside the camera (the book session shows the last capture
    /// in its own pane).
    var showsTextPreview = true
    /// The Recipe · Photo switch, here and in the captures sheet: hidden where every capture is a
    /// page, the contents and Sources pages (ux-notes row 116).
    var showsCaptureMode = true
    /// Done shows before the first page: the book session's way out (ux-notes row 123).
    var alwaysShowsDone = false
    /// Under the top bar: the book session's "Now: …" card.
    var header: AnyView?
    /// Right of the shutter: the book session's figures.
    var trailing: AnyView?

    let session: any PageCaptureSink
    @State private var camera: PageCameraModel
    @State private var isConfirmingClose = false
    @State private var isShowingCaptures = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(session: any PageCaptureSink, confirmsClose: Bool = true, showsTextPreview: Bool = true, showsCaptureMode: Bool = true, alwaysShowsDone: Bool = false,
         header: AnyView? = nil, trailing: AnyView? = nil, onDone: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.session = session
        self.confirmsClose = confirmsClose
        self.showsTextPreview = showsTextPreview
        self.showsCaptureMode = showsCaptureMode
        self.alwaysShowsDone = alwaysShowsDone
        self.header = header
        self.trailing = trailing
        self.onDone = onDone
        self.onClose = onClose
        _camera = State(initialValue: PageCameraModel(session: session))
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                viewfinder
                if showsTextPreview, sizeClass == .regular, geometry.size.width > 900 {
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
        .alert("Clean the Lens?", isPresented: Binding { session.asksToCleanLens } set: { session.asksToCleanLens = $0 }) {
            Button("Continue Anyway", role: .cancel) {}
            Button("Done Cleaning") {}
        } message: {
            Text("The last three pages looked hazy and read poorly. Wipe the camera lens with a soft cloth, then carry on.")
        }
        .confirmationDialog(closeQuestion.title, isPresented: $isConfirmingClose, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: onClose)
            Button("Keep Scanning", role: .cancel) {}
        } message: {
            if let message = closeQuestion.message { Text(message) }
        }
        .sheet(isPresented: $isShowingCaptures) {
            CaptureListSheet(items: session.captureItems, showsMode: showsCaptureMode) { camera.removeCapture(id: $0) } onSetMode: { camera.setMode($1, ofCapture: $0) } onKeep: { session.resolveDuplicates(of: $0, keepNew: $1) } onJoin: { session.resolveJoin(of: $0, join: $1) } onContents: { id, add in
                if add { session.resolveContents(of: id, add: true) } else { camera.removeCapture(id: id) }
            }
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
                // Readings eased into each other (ux-notes row 133).
                .animation(.easeOut(duration: 0.2), value: camera.outline)
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

    /// ✕ at the left, Done at the right, each in a slot of the same width so Flash and Auto sit
    /// centred between them (ux-notes row 140): two separate round glass buttons, each with its
    /// state in colour and a one-word caption (ux-notes row 84).
    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button("Close", systemImage: "xmark") {
                if confirmsClose, session.discardQuestion != nil || camera.pageCount > 0 { isConfirmingClose = true } else { onClose() }
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .frame(width: 44, height: 44)
            .glassEffect(.clear.interactive(), in: .circle)
            .keyboardShortcut(.cancelAction)
            .frame(width: Self.sideSlot, alignment: .leading)

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 18) {
                CameraToggle(title: "Flash", systemImage: camera.flash ? "bolt.fill" : "bolt.slash", tint: .yellow, isOn: $camera.flash)
                    .accessibilityHint("Lights the torch, so any glare shows before you capture.")
                CameraToggle(title: "Auto", systemImage: camera.autoCapture ? "a.circle.fill" : "a.circle", tint: .green, isOn: $camera.autoCapture)
                    .accessibilityLabel("Auto-Capture")
                    .accessibilityHint("Captures a page as soon as it is held still.")
            }

            Spacer(minLength: 0)

            let hidesDone = camera.pageCount == 0 && !alwaysShowsDone
            Button("Done", action: onDone)
                .font(.headline)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                .disabled(hidesDone || camera.preparing > 0)
                .opacity(hidesDone ? 0 : 1)
                .frame(width: Self.sideSlot, alignment: .trailing)
        }
        .foregroundStyle(.white)
    }

    /// The width of the top bar's side slots, ✕'s and Done's alike.
    private static let sideSlot: CGFloat = 88

    /// ✕'s question: the sink's (the book session counts the sitting's captures and the recipes
    /// saved from them), else the pages in the stack.
    private var closeQuestion: (title: String, message: String?) {
        session.discardQuestion ?? (camera.pageCount == 1 ? "Discard the page?" : "Discard \(camera.pageCount) pages?", nil)
    }

    /// The quality pill (advisory: it never stops the shutter), or what to change when no page can
    /// be found (ux-notes row 133), and the book the barcode named.
    private var statusLine: some View {
        VStack(spacing: 8) {
            if let hint = camera.hint {
                HintPill(hint: hint)
            } else if let quality = camera.liveQuality {
                QualityPill(quality: quality)
            }
            if let header {
                header
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
            } else if camera.pageCount == 0, camera.isRunning, session.namesBookByBarcode {
                Text("Show the barcode on the back cover to name the book, or start with a page.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .animation(.default, value: camera.liveQuality)
        .animation(.default, value: camera.hint)
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 14) {
            // Recipe · Photo (ux-notes rows 62 and 82): what the next capture is; a Photo capture is
            // one capture and the switch goes back to Recipe.
            if showsCaptureMode {
                Picker("Capture", selection: $camera.mode) {
                    Text("Recipe").tag(CaptureMode.recipe)
                    Text("Photo").tag(CaptureMode.photo)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityHint("Recipe pages are read; a photo goes with the recipe as a cover, then the camera goes back to Recipe.")
            }

            // Fixed slots either side keep the shutter centred.
            HStack {
                Button {
                    isShowingCaptures = true
                } label: {
                    CaptureStack(thumbnails: camera.thumbnails)
                }
                .buttonStyle(.plain)
                .disabled(camera.thumbnails.isEmpty)
                .accessibilityHint("Shows the captures, to delete one or make it a recipe page or a photo.")
                .frame(width: 88, alignment: .leading)
                Spacer()
                shutter
                Spacer()
                ZStack(alignment: .trailing) { trailing }
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
}

/// What to change when no page can be found (ux-notes row 133): Move closer, More light, Flatten
/// the page, Fill the frame, in amber where the quality pill sits.
private struct HintPill: View {
    let hint: PageOutlineSmoother.Hint

    var body: some View {
        Label(hint.label, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.clear, in: .capsule)
            .accessibilityLabel("No page found: \(hint.label)")
    }

    private var symbol: String {
        switch hint {
        case .moveCloser: "arrow.down.right.and.arrow.up.left"
        case .moreLight: "sun.max"
        case .flattenThePage: "book.pages"
        case .fillTheFrame: "viewfinder"
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

/// iPad: the last capture's text as it is read, so a bad capture shows before the next page: every
/// text block the reader found, in reading order, the ignored ones and the page's furniture dimmed
/// (ux-notes row 87).
private struct CaptureTextPreview: View {
    let session: any PageCaptureSink
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
                VStack(alignment: .leading, spacing: 10) {
                    if session.lastCapturePreview.isEmpty {
                        Text(pageCount == 0 ? "Capture a page and its text appears here as it's read." : "")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.lastCapturePreview) { block in
                        Text(block.text)
                            .foregroundStyle(block.isDimmed ? .tertiary : .primary)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
            }
        }
        .background(.background)
        .environment(\.colorScheme, .dark)
    }
}

/// Flash or Auto: a round glass button, its symbol in colour while on, a one-word caption under it
/// (ux-notes row 84).
private struct CameraToggle: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isOn ? tint : .white)
                    .frame(width: 44, height: 44)
                    .glassEffect(.clear.interactive(), in: .circle)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isOn ? tint : .white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
