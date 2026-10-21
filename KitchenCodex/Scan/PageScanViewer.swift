import Capture
import RecipeModel
import SwiftData
import SwiftUI

/// Detail → View Page (03 §3.3's scanned state): the recipe's page scans with their regions drawn,
/// read-only, in the review's page view. Pinch or double-tap to zoom; several pages swipe.
struct PageScanViewer: View {
    let recipe: Recipe

    @Environment(\.dismiss) private var dismiss
    @State private var model: ScanReviewModel?
    @State private var images: [Int: UIImage] = [:]
    @State private var page = 0
    @State private var showsRegions = true

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    TabView(selection: $page) {
                        ForEach(model.pages) { scan in
                            let image = images[scan.id]
                            ZoomablePage(aspectRatio: image.map { $0.size.width / max(1, $0.size.height) } ?? 3 / 4, focus: nil) {
                                PageRegionsView(
                                    image: image,
                                    regions: showsRegions ? model.regions.filter { $0.page == scan.id } : [],
                                    role: model.shownRole(of:),
                                    label: { region, role in label(region, role, in: model) }
                                )
                            }
                            .tag(scan.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: model.pages.count > 1 ? .always : .never))
                } else {
                    ContentUnavailableView("No Page Scan", systemImage: "doc.viewfinder", description: Text("This recipe wasn't scanned from a page."))
                }
            }
            .background(.background.secondary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $showsRegions) {
                        Label("Regions", systemImage: "rectangle.dashed")
                    }
                    .toggleStyle(.button)
                    .accessibilityHint("Shows or hides what each part of the page became.")
                }
            }
        }
        .task {
            let model = ScanReviewModel(recipe: recipe)
            self.model = model
            for scan in model?.pages ?? [] {
                if let image = await ScanImage.upright(scan, maxPixelSize: 3_000) {
                    images[scan.id] = UIImage(cgImage: image)
                }
            }
        }
    }

    private var title: String {
        guard let pageNumber = model?.pages.first(where: { $0.id == page })?.pageNumber else { return "Page" }
        return "Page \(pageNumber)"
    }

    private func label(_ region: ReviewRegion, _ role: RegionRole?, in model: ScanReviewModel) -> String? {
        if region.isPhoto { return model.stepNumber(forPhoto: region.id).map { "Step \($0) Photo" } ?? role?.label }
        guard let role, role != .furniture, role != .ignore else { return nil }
        if role == .step {
            return model.recipe.steps.firstIndex { $0.regions.first == region.id }.map { "Step \($0 + 1)" }
        }
        let onPage = model.regions.filter { $0.page == region.page && !$0.isPhoto }
        if let index = onPage.firstIndex(where: { $0.id == region.id }), index > 0, onPage[index - 1].role == role { return nil }
        return role.label
    }
}

/// Detail → More → Review Scan, and the review row's Review on a scanned recipe: scan review over
/// the stored page scans, saved as an edit of the recipe (a new version when the content changed)
/// with the review recorded.
struct StoredScanReview: View {
    let recipe: Recipe

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var model: ScanReviewModel?
    @State private var isSaving = false
    @State private var isConfirmingCancel = false
    @State private var isRescanning = false

    var body: some View {
        NavigationStack {
            Group {
                if let model, !isRescanning {
                    ScanReviewView(model: model, bookTitle: recipe.book?.displayTitle, onRescan: rescan, offersSkip: false)
                        .id(ObjectIdentifier(model))
                        .disabled(isSaving)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Review Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        if model?.hasChanges == true { isConfirmingCancel = true } else { dismiss() }
                    }
                    .keyboardShortcut(.cancelAction)
                    .confirmationDialog("Discard changes?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                        Button("Keep Reviewing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Saving without changes is the cook saying it looks right.
                    Button("Save", role: .confirm) { save() }
                        .disabled(isSaving || model?.recipe.title?.text.trimmed.isEmpty != false)
                }
            }
        }
        .interactiveDismissDisabled(model?.hasChanges == true)
        .onAppear { model = ScanReviewModel(recipe: recipe) }
    }

    /// More → Rescan: the stored pages read again, the recipe on them matched by its title.
    private func rescan() {
        guard let model else { return }
        isRescanning = true
        Task {
            let folder = FileManager.default.temporaryDirectory.appending(path: "rescan-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let urls = model.pages.compactMap { page -> URL? in
                let url = folder.appending(path: "page-\(page.id + 1).jpg")
                return (try? page.imageData?.write(to: url)) != nil ? url : nil
            }
            let (_, continuation) = AsyncStream.makeStream(of: PagePipeline.Stage.self)
            if let reading = try? await ScanSession.read(urls, with: ScanSession.makePipeline(), reporting: continuation).first,
               reading.kind == .recipe, !reading.recipes.isEmpty {
                let fresh = ScanReviewModel(reading: reading, urls: urls)
                // The fresh pages keep the stored images, which are upright already.
                for index in fresh.pages.indices where model.pages.indices.contains(index) {
                    fresh.pages[index].imageData = model.pages[index].imageData
                    fresh.pages[index].fileURL = nil
                }
                fresh.current = fresh.recipes.firstIndex { $0.title?.text.localizedCaseInsensitiveCompare(recipe.title) == .orderedSame } ?? 0
                fresh.recipes[fresh.current].reasons = model.recipe.reasons
                fresh.checkpoint()
                self.model = fresh
            }
            isRescanning = false
        }
    }

    private func save() {
        guard let model else { return }
        isSaving = true
        Task {
            await ScanSaving.saveReview(model, of: recipe, images: ScanSaving.PageImages(), in: modelContext)
            dismiss()
        }
    }
}
