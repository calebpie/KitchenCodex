import RecipeModel
import SwiftUI

/// A step photo decoded off the main actor at the size it is shown, cached by image and size.
struct StepPhotoImage: View {
    let image: RecipeImage
    /// Longest side in points.
    var pointSize: CGFloat = 64
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var decoded: UIImage?

    var body: some View {
        ZStack {
            if let decoded {
                Image(uiImage: decoded)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
        .task(id: cacheKey) {
            decoded = await load()
        }
    }

    private var cacheKey: String {
        "step-\(image.id.uuidString)-\(Int(pointSize * displayScale))"
    }

    private func load() async -> UIImage? {
        if let cached = ThumbnailCache.shared.object(forKey: cacheKey as NSString) { return cached }
        guard let data = image.imageData,
              let result = await ImageProcessing.thumbnail(from: data, maxPixelSize: pointSize * displayScale) else { return nil }
        ThumbnailCache.shared.setObject(result, forKey: cacheKey as NSString)
        return result
    }
}

/// The trailing thumbnail on a step in recipe detail (03 §3.3). Shows the first photo, with a count
/// badge when the step has more than one.
struct StepPhotoThumbnail: View {
    let photos: [RecipeImage]
    let stepNumber: Int

    var body: some View {
        StepPhotoImage(image: photos[0], pointSize: 64)
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(alignment: .bottomTrailing) {
                if photos.count > 1 {
                    Text("\(photos.count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.ultraThinMaterial, in: .capsule)
                        .padding(4)
                }
            }
            .contentShape(.rect)
            .accessibilityElement()
            .accessibilityLabel(photos.count == 1 ? "Photo of step \(stepNumber)" : "\(photos.count) photos of step \(stepNumber)")
            .accessibilityHint("Opens the photo full screen.")
            .accessibilityAddTraits(.isButton)
    }
}

/// What the viewer shows: one step's photos.
struct StepPhotoSelection: Identifiable {
    let step: Step
    let stepNumber: Int
    var id: UUID { step.id }
}

/// Full-screen viewer for one step's photos: swipe between them, with a caption line saying which
/// step, which photo, and whose (the source's, or the cook's own).
struct StepPhotoViewer: View {
    let selection: StepPhotoSelection

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private var photos: [RecipeImage] { selection.step.sortedPhotos }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                    StepPhotoImage(image: photo, pointSize: 1_200, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(offset)
                        .accessibilityLabel("Photo \(offset + 1) of \(photos.count), step \(selection.stepNumber)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .background(.black)
            .safeAreaInset(edge: .bottom) {
                caption
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(captionLine)
                .font(.subheadline.weight(.semibold))
            Text(selection.step.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.black.opacity(0.6))
        .accessibilityElement(children: .combine)
    }

    private var captionLine: String {
        var parts = ["Step \(selection.stepNumber)"]
        if photos.count > 1 { parts.append("Photo \(index + 1) of \(photos.count)") }
        if photos.indices.contains(index) {
            let photo = photos[index]
            if !photo.caption.isEmpty { parts.append(photo.caption) }
            parts.append(photo.cookSession == nil ? "From the source" : "Your photo")
        }
        return parts.joined(separator: " · ")
    }
}
