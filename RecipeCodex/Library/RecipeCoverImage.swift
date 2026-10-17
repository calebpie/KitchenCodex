import ImageIO
import RecipeModel
import SwiftUI
import UIKit

/// A recipe's cover, decoded off the main actor at the size it is shown, with a quiet monogram
/// when there is no photo (03 §6 Imagery). Fills whatever frame its parent gives it.
struct RecipeCoverImage: View {
    let recipe: Recipe
    /// Longest side in points; the image is decoded at this size times the display scale.
    var pointSize: CGFloat = 200
    /// The full photo for large views such as the detail hero; cards and rows use the smaller cover copy.
    var usesFullPhoto = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            } else {
                Monogram(title: recipe.title)
            }
        }
        .task(id: cacheKey) {
            image = await load()
        }
    }

    private var maxPixelSize: CGFloat { pointSize * displayScale }

    private var cacheKey: String {
        "\(recipe.id.uuidString)-\(recipe.updatedAt.timeIntervalSinceReferenceDate)-\(Int(maxPixelSize))-\(usesFullPhoto)"
    }

    private func load() async -> UIImage? {
        if let cached = ThumbnailCache.shared.object(forKey: cacheKey as NSString) { return cached }
        let data = usesFullPhoto ? (recipe.coverImage?.imageData ?? recipe.coverImageData) : recipe.coverImageData
        guard let data, let decoded = await ImageProcessing.thumbnail(from: data, maxPixelSize: maxPixelSize) else { return nil }
        ThumbnailCache.shared.setObject(decoded, forKey: cacheKey as NSString)
        return decoded
    }
}

/// The placeholder for a recipe without a photo: its initial in New York on a quiet fill.
struct Monogram: View {
    let title: String

    var body: some View {
        ZStack {
            Rectangle().fill(.fill.tertiary)
            Text(initial)
                .font(.system(.largeTitle, design: .serif, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private var initial: String {
        title.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "R"
    }
}

/// Decoded covers, keyed by recipe, edit time and pixel size.
enum ThumbnailCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()
}

/// Image work that must not run on the main actor.
enum ImageProcessing {
    /// Decodes `data` (JPEG, HEIC, PNG…) with its longest side at most `maxPixelSize`, honoring EXIF orientation.
    @concurrent
    nonisolated static func thumbnail(from data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        downsample(data, maxPixelSize: maxPixelSize).map(UIImage.init(cgImage:))
    }

    /// Re-encodes a photo as JPEG no larger than `maxPixelSize` on its longest side.
    @concurrent
    nonisolated static func jpeg(from data: Data, maxPixelSize: CGFloat, quality: CGFloat) async -> Data? {
        downsample(data, maxPixelSize: maxPixelSize).flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: quality) }
    }

    private nonisolated static func downsample(_ data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
