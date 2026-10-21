import Capture
import PhotosUI
import RecipeModel
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The whole-book session, full screen (03 §3.8, 02 Flow C step 4). iPad: three regions, the
/// punchlist on the left, the camera in the centre and the last capture's structure on the right
/// with its Needs Review toggle, over a status strip ("12 captured · 9 processed · 2 need review ·
/// battery 64%"). iPhone: a compact header ("Now: Leek Soup, p. 114 · 12 of 112") that opens the
/// punchlist as a sheet, the camera filling the rest. Where there is no camera (the Simulator) the
/// centre takes photos and files instead. Close pauses: nothing is lost, and Continue Scanning in
/// Book detail comes back to the next entry not captured.
struct BookScanView: View {
    let book: Book
    /// Scan now: the session opens at this entry.
    var startAt: BookEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var session: BookScanSession?
    @State private var isShowingList = false
    @State private var isReviewing = false
    @State private var isConfirmingClose = false
    @State private var cameraState = CameraState.checking

    enum CameraState {
        case checking, ready, denied, unavailable
    }

    var body: some View {
        GeometryReader { geometry in
            if let session {
                if sizeClass == .regular, geometry.size.width > 900 {
                    wide(session)
                } else {
                    compact(session)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .task {
            let session = BookScanStore.shared.session(for: book, context: modelContext)
            session.open(at: startAt)
            self.session = session
            if CameraAccess.isAvailable {
                cameraState = CameraAccess.isDenied ? .denied : (await CameraAccess.request() ? .ready : .denied)
            } else {
                cameraState = .unavailable
            }
        }
        .onDisappear { session?.pause() }
        .sheet(isPresented: $isShowingList) {
            if let session {
                NavigationStack {
                    PunchlistPane(session: session) { isShowingList = false }
                        .navigationTitle(book.displayTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", role: .confirm) { isShowingList = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $isReviewing) {
            BookReviewQueueView(book: book)
        }
        .alert("Clean the Lens?", isPresented: Binding { session?.asksToCleanLens == true && cameraState != .ready } set: { session?.asksToCleanLens = $0 }) {
            Button("Continue Anyway", role: .cancel) {}
        } message: {
            Text("The last three pages looked hazy and read poorly.")
        }
    }

    // MARK: - iPad

    private func wide(_ session: BookScanSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        closeButton(session)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.displayTitle)
                                .font(.headline)
                                .lineLimit(1)
                            Text(progressLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    PunchlistPane(session: session)
                }
                .frame(width: 330)
                Divider()
                centre(session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                LastCapturePane(session: session)
                    .frame(width: 340)
            }
            Divider()
            statusStrip(session)
        }
    }

    // MARK: - iPhone

    private func compact(_ session: BookScanSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                closeButton(session)
                Button {
                    isShowingList = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowLine(session))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(progressLine) · Show List")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the recipe list.")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
            centre(session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if cameraState != .ready {
                LastCaptureCard(session: session)
            }
            statusStrip(session)
        }
    }

    // MARK: - Shared

    private func closeButton(_ session: BookScanSession) -> some View {
        Button("Close", systemImage: "xmark") {
            // Asks only when this sitting added to the queue; what waited before waits in the book.
            if session.needReviewCount > 0, session.shownCaptures.contains(where: { session.needsReview($0) }) {
                isConfirmingClose = true
            } else {
                dismiss()
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .frame(width: 44, height: 44)
        .keyboardShortcut(.cancelAction)
        .confirmationDialog(session.needReviewCount == 1 ? "1 recipe needs review" : "\(session.needReviewCount) recipes need review", isPresented: $isConfirmingClose, titleVisibility: .visible) {
            Button("Review Now") { isReviewing = true }
            Button("Later") { dismiss() }
        } message: {
            Text("Everything captured is saved. The review queue waits in the book's detail.")
        }
    }

    @ViewBuilder
    private func centre(_ session: BookScanSession) -> some View {
        switch cameraState {
        case .ready:
            PageCameraView(session: session, confirmsClose: false, showsTextPreview: false, showsClose: false, onDone: nil) { dismiss() }
        case .checking:
            ProgressView()
        case .denied, .unavailable:
            CaptureIntake(session: session, isCameraDenied: cameraState == .denied)
        }
    }

    /// "12 of 112 captured".
    private var progressLine: String {
        let progress = book.punchlistProgress
        return "\(progress.captured) of \(progress.total) captured"
    }

    /// "Now: Leek Soup, p. 114".
    private func nowLine(_ session: BookScanSession) -> String {
        guard let entry = session.currentEntry else { return "Every listed recipe is captured" }
        return "Now: \(entry.displayTitle)" + (entry.page.map { ", p. \($0)" } ?? "")
    }

    private func statusStrip(_ session: BookScanSession) -> some View {
        StatusStrip(session: session) { isReviewing = true }
    }
}

/// "12 captured · 9 processed · 2 need review · battery 64%", with Review once there is something
/// to review (03 §3.8).
private struct StatusStrip: View {
    let session: BookScanSession
    var onReview: () -> Void

    @State private var battery: Float = -1

    var body: some View {
        HStack(spacing: 12) {
            if session.isReadingCaptures {
                ProgressView()
                    .controlSize(.small)
            }
            Text(line)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            if session.needReviewCount > 0 {
                Button("Review", systemImage: "rectangle.and.text.magnifyingglass", action: onReview)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            battery = UIDevice.current.batteryLevel
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            battery = UIDevice.current.batteryLevel
        }
    }

    private var line: String {
        var parts = ["\(session.capturedCount) captured", "\(session.processedCount) processed",
                     session.needReviewCount == 1 ? "1 needs review" : "\(session.needReviewCount) need review"]
        // The Simulator has no battery to report (-1).
        if battery >= 0 { parts.append("battery \(Int((battery * 100).rounded()))%") }
        if let refining = session.refining { parts.append(refining.isEmpty ? "Apple Intelligence is reading a recipe" : "Apple Intelligence is reading “\(refining)”") }
        return parts.joined(separator: " · ")
    }
}

/// The centre region where there is no camera (the Simulator, or camera access off): photos from
/// Photos or Files go into the session as captures do, with the same Recipe · Photo switch, which
/// goes back to Recipe after a Photo (ux-notes row 82), and the same captures sheet.
private struct CaptureIntake: View {
    let session: BookScanSession
    var isCameraDenied: Bool

    @State private var mode = CaptureMode.recipe
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isChoosingPhotos = false
    @State private var isChoosingFiles = false
    @State private var isShowingCaptures = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isCameraDenied {
                    VStack(spacing: 8) {
                        Text("Camera access is off for Kitchen Codex. Turn it on in Settings to scan with the camera, or choose photos of the pages.")
                            .multilineTextAlignment(.center)
                        Button("Open Settings") { CameraAccess.openSettings() }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Picker("Capture", selection: $mode) {
                    Text("Recipe").tag(CaptureMode.recipe)
                    Text("Photo").tag(CaptureMode.photo)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .accessibilityHint("Recipe pages are read; a photo goes with the recipe as a cover, then this goes back to Recipe.")
                HStack(spacing: 16) {
                    Button { isChoosingPhotos = true } label: {
                        Label("From Photo", systemImage: "photo.on.rectangle")
                            .frame(minWidth: 120)
                    }
                    Button { isChoosingFiles = true } label: {
                        Label("Files", systemImage: "folder")
                            .frame(minWidth: 120)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text(mode == .photo
                     ? "The next photos go with the recipe they show, or the one before, as cover candidates."
                     : "Choose the recipe pages in order. Each is read and saved as it comes in, and the list keeps up by the page numbers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                if !session.captureItems.isEmpty {
                    Button(session.captureItems.count == 1 ? "1 Capture" : "\(session.captureItems.count) Captures", systemImage: "square.stack") {
                        isShowingCaptures = true
                    }
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
        }
        .photosPicker(isPresented: $isChoosingPhotos, selection: $photoItems, maxSelectionCount: 30, selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared())
        .fileImporter(isPresented: $isChoosingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            session.add(files: urls, mode: mode)
            mode = .recipe
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            let chosen = mode
            photoItems = []
            mode = .recipe
            Task { await session.add(photos: items, mode: chosen) }
        }
        .sheet(isPresented: $isShowingCaptures) {
            CaptureListSheet(items: session.captureItems) { session.removeCapture(id: $0) } onSetMode: { session.setMode($1, ofCapture: $0) } onSetNeedsReview: { session.setNeedsReview($1, for: $0) } onKeep: { session.resolveDuplicates(of: $0, keepNew: $1) } onJoin: { session.resolveJoin(of: $0, join: $1) }
        }
    }
}

/// iPad's right region: the last capture's structure as read (title, yield, ingredients, steps),
/// every other text block dimmed after it, and the Needs Review toggle (03 §3.8).
struct LastCapturePane: View {
    let session: BookScanSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Last Capture")
                    .font(.headline)
                Spacer()
                if session.isReadingCaptures {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading…")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            if let capture = session.lastCapture {
                Toggle("Needs Review", isOn: Binding { session.needsReview(capture) } set: { session.setNeedsReview($0, for: capture.id) })
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                if let detail = capture.status == .pending ? "Reading…" : capture.detail {
                    Text("\(capture.note) · \(detail)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            Divider()
            ScrollView {
                if let capture = session.lastCapture, let reading = session.readings[capture.id] {
                    CaptureStructure(reading: reading, isPhoto: capture.mode == .photo)
                        .padding()
                } else {
                    Text("Capture a recipe page and what was read shows here.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
        .background(Color(.systemBackground))
    }
}

/// iPhone where there is no camera: the last capture in a line, with its Needs Review toggle.
private struct LastCaptureCard: View {
    let session: BookScanSession

    var body: some View {
        if let capture = session.lastCapture {
            VStack(alignment: .leading, spacing: 6) {
                Text("Last: \(capture.note) · \(capture.status == .pending ? "Reading…" : capture.detail ?? "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Toggle("Needs Review", isOn: Binding { session.needsReview(capture) } set: { session.setNeedsReview($0, for: capture.id) })
                    .font(.subheadline)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

/// A reading's recipes as structure, then every other text block dimmed.
private struct CaptureStructure: View {
    let reading: PageReading
    var isPhoto: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isPhoto || reading.kind == .photo {
                Text(reading.pageNumber.map { "A photo, p. \($0)" } ?? "A photo")
                    .foregroundStyle(.secondary)
            } else if reading.kind != .recipe {
                Text(reading.kind.title)
                    .foregroundStyle(.secondary)
            }
            if !isPhoto {
                ForEach(Array(reading.recipes.enumerated()), id: \.offset) { _, recipe in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipe.title.isEmpty ? "Untitled" : recipe.title)
                            .font(.title3.bold())
                        if let yield = recipe.yield {
                            Text(yield).foregroundStyle(.secondary)
                        }
                        if !recipe.ingredients.isEmpty {
                            Text("Ingredients").font(.subheadline.weight(.semibold)).padding(.top, 4)
                            ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, ingredient in
                                Text(ingredient.text)
                                    .foregroundStyle(ingredient.isUnparsed ? Color.orange : Color.primary)
                            }
                        }
                        if !recipe.steps.isEmpty {
                            Text("Steps").font(.subheadline.weight(.semibold)).padding(.top, 4)
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                Text("\(index + 1). \(step.text)")
                            }
                        }
                    }
                }
                let other = otherBlocks
                if !other.isEmpty {
                    Text("Also on the page").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(other) { block in
                        Text(block.text).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    /// Text blocks that are none of the structure: the headnote, notes, the page's furniture, what
    /// nothing claimed.
    private var otherBlocks: [CapturePreviewBlock] {
        let shown: Set<PageBlock.Role> = [.title, .yield, .ingredient, .ingredientGroup, .step]
        return reading.blocks.filter { $0.kind != .photo && !($0.role.map(shown.contains) ?? false) && !$0.text.isEmpty }
            .map { CapturePreviewBlock(id: $0.id, text: $0.text, isDimmed: true) }
    }
}
