import Capture
import SwiftUI

extension RegionRole {
    /// The region's colour (03 §3.6): semantic, by kind of block, and always with a label.
    var color: Color {
        switch self {
        case .title: .purple
        case .ingredient, .ingredientGroup: .blue
        case .step: .green
        case .headnote: .gray
        case .yield, .time: .orange
        case .note: .brown
        case .stepPhoto: .pink
        case .cover: .yellow
        case .crossReference: .indigo
        case .furniture, .ignore: .secondary
        }
    }
}

/// A page scan with its regions drawn over it (03 §3.6): a translucent fill in the region's colour
/// and a label where a run of one kind starts ("Ingredients", "Step 2"), unassigned text and
/// printed photos outlined. Scan review taps, lassos and hovers on it; View Page only looks.
struct PageRegionsView<Popover: View>: View {
    let image: UIImage?
    let regions: [ReviewRegion]
    /// The role each region shows.
    var role: (ReviewRegion) -> RegionRole? = { $0.role }
    /// The label for a region that starts a run: its role's, or "Step 3".
    var label: (ReviewRegion, RegionRole?) -> String? = { _, role in role?.label }
    /// Regions of another recipe on the page.
    var isDimmed: (ReviewRegion) -> Bool = { _ in false }
    var selected: Set<Int> = []
    var flashing: Set<Int> = []
    var onTap: ((ReviewRegion) -> Void)?
    /// iPad: regions inside a lasso drawn over the page.
    var onLasso: (([ReviewRegion]) -> Void)?
    /// iPad: the region a popover points at, and what it shows.
    var popoverRegion: Binding<Int?>?
    @ViewBuilder var popover: (Int) -> Popover

    @State private var lasso: [CGPoint] = []
    @State private var hovered: ReviewRegion?
    @State private var flashOn = false

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .accessibilityHidden(true)
                } else {
                    Rectangle().fill(.fill.tertiary)
                        .overlay { ProgressView() }
                }
            }
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    ZStack(alignment: .topLeading) {
                        // Larger regions first, so a small one inside another (a bold label in its
                        // paragraph's box) sits on top and takes its own taps.
                        ForEach(regions.sorted { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }) { region in
                            regionView(region, in: size)
                        }
                        if lasso.count > 1 {
                            Path { path in path.addLines(lasso); path.closeSubpath() }
                                .stroke(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                .fill(.tint.opacity(0.08))
                                .allowsHitTesting(false)
                        }
                        if let hovered, let text = Optional(hovered.text), !text.isEmpty {
                            hoverPreview(text, for: hovered, in: size)
                        }
                    }
                    .contentShape(.rect)
                    // One tap for the page: the smallest region under the finger, so a label inside
                    // its paragraph's box is reachable (Combine's two pieces of a note, row 88).
                    // Alongside the page's double tap to zoom, which an exclusive tap here would
                    // swallow.
                    .simultaneousGesture(SpatialTapGesture().onEnded { value in
                        if let onTap, let region = region(at: value.location, in: size) { onTap(region) }
                    })
                    .gesture(lassoGesture(in: size), isEnabled: onLasso != nil)
                    .onContinuousHover { phase in
                        // Pencil hover (and the pointer) previews a region's text on iPad.
                        guard onLasso != nil else { return }
                        switch phase {
                        case let .active(point): hovered = region(at: point, in: size)
                        case .ended: hovered = nil
                        }
                    }
                }
            }
            .onChange(of: flashing) { _, ids in
                guard !ids.isEmpty else { return }
                flashOn = true
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    withAnimation(.easeOut(duration: 0.4)) { flashOn = false }
                }
            }
    }

    private var aspectRatio: CGFloat {
        guard let image, image.size.height > 0 else { return 3 / 4 }
        return image.size.width / image.size.height
    }

    private func frame(of region: ReviewRegion, in size: CGSize) -> CGRect {
        CGRect(x: region.rect.minX * size.width, y: region.rect.minY * size.height,
               width: region.rect.width * size.width, height: region.rect.height * size.height)
            .insetBy(dx: -2, dy: -2)
    }

    @ViewBuilder
    private func regionView(_ region: ReviewRegion, in size: CGSize) -> some View {
        let frame = frame(of: region, in: size)
        let role = role(region)
        let isFlashing = flashOn && flashing.contains(region.id)
        let isSelected = selected.contains(region.id)
        let color = role?.color ?? (region.isPhoto ? .secondary : .orange)
        let outlined = role == nil || role == .ignore || role == .furniture
        let shape = RoundedRectangle(cornerRadius: 3)
        ZStack(alignment: .topLeading) {
            shape
                .fill(outlined ? Color.clear : color.opacity(isFlashing ? 0.55 : 0.22))
            shape
                .strokeBorder(isSelected || isFlashing ? Color.accentColor : color.opacity(outlined ? 0.7 : 0.6),
                              style: StrokeStyle(lineWidth: isSelected || isFlashing ? 2.5 : 1, dash: outlined ? [4, 3] : []))
            if let text = label(region, role) {
                Text(text)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(color.opacity(outlined ? 0.75 : 0.9), in: .capsule)
                    .fixedSize()
                    .offset(y: -12)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .opacity(isDimmed(region) ? 0.25 : 1)
        // Taps are the page's (above); the region only shows.
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel(region, role: role))
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityAction { onTap?(region) }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHidden(role == .furniture)
        .popover(isPresented: popoverBinding(for: region.id)) {
            popover(region.id)
        }
        // Placed, not offset, so the tap target and VoiceOver's frame are where the region is.
        .position(x: frame.midX, y: frame.midY)
    }

    private func popoverBinding(for id: Int) -> Binding<Bool> {
        Binding {
            popoverRegion?.wrappedValue == id
        } set: { isShown in
            if !isShown, popoverRegion?.wrappedValue == id { popoverRegion?.wrappedValue = nil }
        }
    }

    private func accessibilityLabel(_ region: ReviewRegion, role: RegionRole?) -> String {
        let kind = role?.label ?? (region.isPhoto ? "Printed photo" : "Unassigned")
        return region.isPhoto ? kind : "\(kind): \(region.text)"
    }

    private func hoverPreview(_ text: String, for region: ReviewRegion, in size: CGSize) -> some View {
        let frame = frame(of: region, in: size)
        return Text(text)
            .font(.caption)
            .lineLimit(4)
            .padding(8)
            .frame(maxWidth: 280, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 10))
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: min(frame.minX, max(0, size.width - 280)), y: frame.maxY + 4)
            .allowsHitTesting(false)
    }

    /// The smallest region under `point`, as the taps find it.
    private func region(at point: CGPoint, in size: CGSize) -> ReviewRegion? {
        regions.filter { frame(of: $0, in: size).contains(point) && role($0) != .furniture }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
    }

    /// The area a closed stroke encloses (the shoelace formula).
    private static func area(of points: [CGPoint]) -> CGFloat {
        guard points.count > 2 else { return 0 }
        var sum: CGFloat = 0
        for (index, point) in points.enumerated() {
            let next = points[(index + 1) % points.count]
            sum += point.x * next.y - next.x * point.y
        }
        return abs(sum) / 2
    }

    private func lassoGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in lasso.append(value.location) }
            .onEnded { _ in
                var path = Path { $0.addLines(lasso); $0.closeSubpath() }
                // A stroke that encloses next to nothing (a diagonal drag) selects its box.
                let box = path.boundingRect
                if Self.area(of: lasso) < box.width * box.height * 0.15 { path = Path(box) }
                let inside = regions.filter { region in
                    let frame = frame(of: region, in: size)
                    return role(region) != .furniture && path.contains(CGPoint(x: frame.midX, y: frame.midY))
                }
                lasso = []
                if !inside.isEmpty { onLasso?(inside) }
            }
    }
}

extension PageRegionsView where Popover == EmptyView {
    /// The page with its regions, read-only (View Page).
    init(image: UIImage?, regions: [ReviewRegion], role: @escaping (ReviewRegion) -> RegionRole? = { $0.role },
         label: @escaping (ReviewRegion, RegionRole?) -> String? = { _, role in role?.label }) {
        self.init(image: image, regions: regions, role: role, label: label, popover: { _ in EmptyView() })
    }
}

/// A page scan that zooms: pinch, or double-tap to zoom in and out, and scrolls to a region asked
/// for (an item's source in review).
struct ZoomablePage<Content: View>: View {
    var aspectRatio: CGFloat
    /// A region to bring into view, in unit page coordinates.
    var focus: CGRect?
    @ViewBuilder var content: Content

    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var position = ScrollPosition()

    var body: some View {
        GeometryReader { geometry in
            let fitted = fittedSize(in: geometry.size)
            let scale = min(5, max(1, zoom * pinch))
            ScrollView([.horizontal, .vertical]) {
                content
                    .frame(width: fitted.width * scale, height: fitted.height * scale)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .scrollPosition($position)
            .scrollIndicators(.hidden)
            // At fit size there is nothing to pan, so a drag is the iPad's lasso, not a scroll.
            .scrollDisabled(zoom <= 1 && pinch == 1)
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = min(5, max(1, zoom * value.magnification)) }
            )
            .onTapGesture(count: 2) {
                withAnimation { zoom = zoom > 1.2 ? 1 : 2.5 }
            }
            .onChange(of: focus) { _, rect in
                guard let rect else { return }
                if zoom < 1.8 { zoom = 2.2 }
                let width = fitted.width * zoom, height = fitted.height * zoom
                let x = max(0, rect.midX * width - geometry.size.width / 2)
                let y = max(0, rect.midY * height - geometry.size.height / 2)
                withAnimation { position.scrollTo(point: CGPoint(x: x, y: y)) }
            }
        }
    }

    private func fittedSize(in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        if size.width / size.height > aspectRatio {
            return CGSize(width: size.height * aspectRatio, height: size.height)
        }
        return CGSize(width: size.width, height: size.width / aspectRatio)
    }
}
