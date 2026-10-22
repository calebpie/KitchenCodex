import Capture
import PhotosUI
import RecipeModel
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The whole-book session, full screen (03 §3.8, 02 Flow C step 4). Its camera page mirrors Scan
/// Page's (ux-notes row 123): the camera full bleed, Done at the top right saving what was captured
/// and closing (asking first when the sitting sent recipes to the review queue), ✕ at the top left
/// discarding this sitting's captures after a warning that says how many, and the recipes saved
/// from them; "Now: …", the count and Show List on a glass card under the top bar; the strip's four
/// figures (captured, processed, need review, battery) stacked right of the shutter (row 134).
/// iPad: three regions, the punchlist on the left, the camera in the centre and the last capture's
/// structure on the right with its Needs Review pill. Where there is no camera (the Simulator) the
/// centre takes photos and files instead, with ✕ and Done in the header and the status strip
/// ("12 captured · 9 processed · 2 need review · battery 64%") at the foot. Done pauses: nothing
/// is lost, and Continue Scanning in Book detail comes back to the next entry not captured.
struct BookScanView: View {
    let book: Book
    /// Scan now: the session opens at this entry.
    var startAt: BookEntry?
    /// Recipe pages offered as contents pages (Scan It as a Recipe, ux-notes row 114): the
    /// session's first captures.
    var firstPages: [URL] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var session: BookScanSession?
    @State private var isShowingList = false
    @State private var isReviewing = false
    @State private var isConfirmingDone = false
    @State private var isConfirmingDiscard = false
    @State private var cameraState = CameraState.checking
    @State private var hasTakenFirstPages = false

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
        .background(cameraState == .ready ? Color.black : Color(.systemGroupedBackground))
        .task {
            let session = BookScanStore.shared.session(for: book, context: modelContext)
            // One sitting per presentation: the view coming back resumes it.
            if self.session == nil { session.open(at: startAt) } else { session.resume() }
            self.session = session
            if !firstPages.isEmpty, !hasTakenFirstPages {
                hasTakenFirstPages = true
                session.add(files: firstPages, mode: .recipe)
            }
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
        .reviewPresentation(isPresented: $isReviewing) {
            // Rescan: back to this camera at the recipe's entry.
            BookReviewQueueView(book: book) { entry in
                isReviewing = false
                if let entry { session?.select(entry) }
            }
        }
        .alert("Clean the Lens?", isPresented: Binding { session?.asksToCleanLens == true && cameraState != .ready } set: { session?.asksToCleanLens = $0 }) {
            Button("Continue Anyway", role: .cancel) {}
        } message: {
            Text("The last three pages looked hazy and read poorly.")
        }
        // Done asks only when this sitting added to the queue; what waited before waits in the book.
        .confirmationDialog(session.map { $0.needReviewCount == 1 ? "1 recipe needs review" : "\($0.needReviewCount) recipes need review" } ?? "", isPresented: $isConfirmingDone, titleVisibility: .visible) {
            Button("Review Now") { isReviewing = true }
            Button("Later") { dismiss() }
        } message: {
            Text("Everything captured is saved. The review queue waits in the book's detail.")
        }
        // ✕ where there is no camera; the camera asks its own.
        .confirmationDialog(session?.discardQuestion?.title ?? "", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { discard() }
            Button("Keep Scanning", role: .cancel) {}
        } message: {
            if let message = session?.discardQuestion?.message { Text(message) }
        }
    }

    // MARK: - iPad

    private func wide(_ session: BookScanSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        if cameraState != .ready { closeButton(session) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.displayTitle)
                                .font(.headline)
                                .lineLimit(1)
                            Text(progressLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if cameraState != .ready { doneButton(session) }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    PunchlistPane(session: session)
                }
                .frame(width: 330)
                .background(Color(.systemGroupedBackground))
                Divider()
                centre(session, header: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                LastCapturePane(session: session)
                    .frame(width: 340)
            }
            if cameraState != .ready {
                Divider()
                statusStrip(session)
            }
        }
    }

    // MARK: - iPhone

    @ViewBuilder
    private func compact(_ session: BookScanSession) -> some View {
        if cameraState == .ready {
            // The camera full bleed, its controls over it (ux-notes row 123).
            centre(session, header: true)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    closeButton(session)
                    nowButton(session)
                    doneButton(session)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
                centre(session, header: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                LastCaptureCard(session: session)
                statusStrip(session)
            }
        }
    }

    // MARK: - Shared

    /// ✕: this sitting's captures discarded, after the warning when there are any.
    private func closeButton(_ session: BookScanSession) -> some View {
        Button("Discard This Sitting", systemImage: "xmark") {
            if session.discardQuestion != nil { isConfirmingDiscard = true } else { dismiss() }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .frame(width: 44, height: 44)
        .keyboardShortcut(.cancelAction)
    }

    /// Done: what was captured is saved and the session closes.
    private func doneButton(_ session: BookScanSession) -> some View {
        Button("Done") { finish(session) }
            .font(.headline)
    }

    /// "Now: Leek Soup, p. 114" over "12 of 112 captured · Show List": the list as a sheet.
    private func nowButton(_ session: BookScanSession) -> some View {
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

    /// The same over the camera: light text on a glass card, the camera's dim layer behind it.
    private func nowCard(_ session: BookScanSession) -> some View {
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
                    .opacity(0.85)
                if let refining = session.refining {
                    Text(refining.isEmpty ? "Apple Intelligence is reading a recipe" : "Apple Intelligence is reading “\(refining)”")
                        .font(.caption)
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the recipe list.")
    }

    /// Done: the review question when this sitting sent recipes to the queue, else closed.
    private func finish(_ session: BookScanSession) {
        if session.needReviewCount > 0, session.shownCaptures.contains(where: { session.needsReview($0) }) {
            isConfirmingDone = true
        } else {
            dismiss()
        }
    }

    /// ✕, answered Discard.
    private func discard() {
        session?.discardSitting()
        dismiss()
    }

    @ViewBuilder
    private func centre(_ session: BookScanSession, header: Bool) -> some View {
        switch cameraState {
        case .ready:
            PageCameraView(session: session, showsTextPreview: false, alwaysShowsDone: true,
                           header: header ? AnyView(nowCard(session)) : nil,
                           trailing: AnyView(SessionFigures(session: session))) {
                finish(session)
            } onClose: {
                discard()
            }
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
        // No recipes listed: the list grows as pages are scanned (ux-notes rows 114, 117).
        if book.orderedEntries.isEmpty { return "Recipes are added as you scan" }
        guard let entry = session.currentEntry else { return "Every listed recipe is captured" }
        return "Now: \(entry.displayTitle)" + (entry.page.map { ", p. \($0)" } ?? "")
    }

    private func statusStrip(_ session: BookScanSession) -> some View {
        StatusStrip(session: session) { isReviewing = true }
    }
}

/// Right of the shutter (ux-notes row 134): the strip's four figures stacked, captured, processed,
/// need review (in orange while there are any) and battery.
private struct SessionFigures: View {
    let session: BookScanSession

    /// -1 where there is no battery to report (the Simulator).
    @State private var battery: Float = -1

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                if session.isReadingCaptures {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }
                Text("\(session.capturedCount) captured")
            }
            Text("\(session.processedCount) processed")
            Text(session.needReviewCount == 1 ? "1 needs review" : "\(session.needReviewCount) need review")
                .foregroundStyle(session.needReviewCount > 0 ? Color.orange : Color.white)
            if battery >= 0 {
                Text("battery \(Int((battery * 100).rounded()))%")
            }
        }
        .font(.caption2.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassEffect(.clear, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            battery = UIDevice.current.batteryLevel
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            battery = UIDevice.current.batteryLevel
        }
    }
}

/// "12 captured · 9 processed · 2 need review · battery 64%", with Review once there is something
/// to review (03 §3.8): where there is no camera, at the session's foot.
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
            CaptureListSheet(items: session.captureItems) { session.removeCapture(id: $0) } onSetMode: { session.setMode($1, ofCapture: $0) } onKeep: { session.resolveDuplicates(of: $0, keepNew: $1) } onJoin: { session.resolveJoin(of: $0, join: $1) } onContents: { session.resolveContents(of: $0, add: $1) }
        }
    }
}

/// iPad's right region: the last capture's structure as read (title, yield, ingredients, steps),
/// every other text block dimmed after it, and its Needs Review pill (03 §3.8; a pill, not a
/// toggle, as in the captures sheet, ux-notes row 135).
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
                if session.needsReview(capture), !capture.recipes.isEmpty || !capture.references.isEmpty {
                    NeedsReviewPill()
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
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

/// iPhone where there is no camera: the last capture in a line, with its Needs Review pill.
private struct LastCaptureCard: View {
    let session: BookScanSession

    var body: some View {
        if let capture = session.lastCapture {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Last: \(capture.note) · \(capture.status == .pending ? "Reading…" : capture.detail ?? "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if session.needsReview(capture), !capture.recipes.isEmpty || !capture.references.isEmpty {
                    NeedsReviewPill()
                }
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
