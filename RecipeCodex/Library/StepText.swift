import RecipeModel
import SwiftUI
import UIKit
import Units

/// A step's text as written, with each temperature shown as a pill in the cook's preferred unit
/// (03 §3.3 and §3.12, 04 §5.1 Temperatures): "Roast at 220°C (200°C fan)" reads "Roast at 425°F"
/// for a Fahrenheit cook. The original wording is kept; the edit menu shows it as written.
/// `StepTextView` lays the text out; this type finds the temperatures and what they read.
enum StepText {
    enum Part: Equatable {
        case text(String)
        /// What the pill shows, and the words it stands for.
        case temperature(shown: String, original: String)
    }

    /// The text split around every temperature `TemperatureParser` finds.
    static func parts(of text: String, in scale: TemperatureScale) -> [Part] {
        var parts: [Part] = []
        var position = text.startIndex
        for mention in TemperatureParser.mentions(in: text) {
            if position < mention.range.lowerBound {
                parts.append(.text(String(text[position..<mention.range.lowerBound])))
            }
            parts.append(.temperature(shown: shown(mention.temperature, in: scale), original: mention.originalText))
            position = mention.range.upperBound
        }
        if position < text.endIndex {
            parts.append(.text(String(text[position...])))
        }
        return parts
    }

    /// What a temperature's pill reads. Alternatives that are the same temperature in other units
    /// ("350 °F / 177 °C", "180°C/gas 4") read as one, chosen by `ParsedTemperature.displayed(in:)`;
    /// different ones stay apart: "450°F (230°C) or 400°F (200°C) if using convection" reads
    /// "450°F or 400°F", not "450°F" alone. Fan values give way to conventional ones, as in Units.
    static func shown(_ temperature: ParsedTemperature, in scale: TemperatureScale, style: TemperatureNameStyle = .abbreviated) -> String {
        let conventional = temperature.alternatives.filter { !$0.fan }
        let candidates = conventional.isEmpty ? temperature.alternatives : conventional
        var groups: [[Temperature]] = []
        for alternative in candidates {
            let fahrenheit = alternative.converted(to: .fahrenheit).degrees
            if let index = groups.firstIndex(where: { ($0[0].converted(to: .fahrenheit).degrees - fahrenheit).magnitude <= sameTemperatureSpread }) {
                groups[index].append(alternative)
            } else {
                groups.append([alternative])
            }
        }
        return groups
            .map { ParsedTemperature(alternatives: $0, originalText: temperature.originalText).formatted(in: scale, style: style) }
            .joined(separator: " or ")
    }

    /// Degrees Fahrenheit within which two written values are one temperature in two units:
    /// 230°C is 446°F beside 450°F, and gas 4 is 350°F beside 180°C (356°F). A convection
    /// alternative sits 25°F lower.
    static let sameTemperatureSpread = Rational(12)

    /// The step as VoiceOver should read it: temperatures in the preferred unit, spelled out.
    static func spoken(_ text: String, in scale: TemperatureScale) -> String {
        var result = ""
        var position = text.startIndex
        for mention in TemperatureParser.mentions(in: text) {
            result += text[position..<mention.range.lowerBound]
            result += shown(mention.temperature, in: scale, style: .full)
            position = mention.range.upperBound
        }
        return result + text[position...]
    }

    /// Temperatures whose pill differs from what the recipe wrote, as (shown, original) pairs.
    static func conversions(in text: String, scale: TemperatureScale) -> [(shown: String, original: String)] {
        parts(of: text, in: scale).compactMap { part in
            guard case let .temperature(shown, original) = part, shown != original else { return nil }
            return (shown, original)
        }
    }
}

extension TemperaturePreference {
    /// The Units package's scale for this preference.
    var temperatureScale: TemperatureScale {
        switch self {
        case .fahrenheit: .fahrenheit
        case .celsius: .celsius
        }
    }
}

// MARK: - Layout

/// A step's body, laid out by TextKit 2 so it can flow around the step's thumbnail (04 §5.1 Step
/// photos): the first lines run beside a rect of `exclusion` size at the top trailing corner, and
/// once the text passes its bottom it runs the full width. SwiftUI `Text` cannot wrap around a
/// view, so this is a non-editable, non-scrolling `UITextView` with an exclusion path. It keeps
/// Dynamic Type, text selection, the temperature pills (capsules drawn behind the ranges
/// `StepText` finds) and As Written, which joins the edit menu for a selected temperature.
struct StepTextView: View {
    let text: String
    let scale: TemperatureScale
    /// The thumbnail the text flows around, or nil for none.
    var exclusion: CGSize?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let font = StepTextLayout.font(for: dynamicTypeSize)
        StepTextLayout(text: text, scale: scale, exclusion: exclusion, font: font)
            // The step number sits on the first line's baseline.
            .alignmentGuide(.firstTextBaseline) { _ in font.ascender }
    }
}

private struct StepTextLayout: UIViewRepresentable {
    let text: String
    let scale: TemperatureScale
    let exclusion: CGSize?
    let font: UIFont

    /// The body style at the environment's Dynamic Type size.
    static func font(for size: DynamicTypeSize) -> UIFont {
        UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size)))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> StepUITextView {
        // TextKit 2: the default for a text view made without a container.
        let view = StepUITextView(frame: .zero, textContainer: nil)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = false
        view.tintColor = UIColor(Color.accentColor)
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: StepUITextView, context: Context) {
        let (attributed, pills) = Self.attributedText(text, scale: scale, font: font)
        context.coordinator.pills = pills
        view.configure(text: attributed, pills: pills.map(\.range), exclusion: exclusion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: StepUITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: view.height(forWidth: width))
    }

    /// The step with each temperature as a semibold, tinted run padded by narrow no-break spaces,
    /// and where each run is, with what the recipe wrote.
    static func attributedText(_ text: String, scale: TemperatureScale, font: UIFont) -> (NSAttributedString, [Coordinator.Pill]) {
        let result = NSMutableAttributedString()
        var pills: [Coordinator.Pill] = []
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
        let pill: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: UIColor(Color.accentColor),
        ]
        for part in StepText.parts(of: text, in: scale) {
            switch part {
            case let .text(words):
                result.append(NSAttributedString(string: words, attributes: plain))
            case let .temperature(shown, original):
                let run = NSAttributedString(string: "\u{202F}\(shown)\u{202F}", attributes: pill)
                pills.append(.init(range: NSRange(location: result.length, length: run.length), shown: shown, original: original))
                result.append(run)
            }
        }
        return (result, pills)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        struct Pill {
            let range: NSRange
            let shown: String
            let original: String
        }

        var pills: [Pill] = []

        /// A selection that touches a converted temperature offers it as written.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            let written = pills.filter { $0.shown != $0.original && NSIntersectionRange($0.range, range).length > 0 }
            guard !written.isEmpty else { return nil }
            let items = written.map { pill in
                UIAction(title: "As Written: \(pill.original)", image: UIImage(systemName: "thermometer.medium")) { _ in }
            }
            return UIMenu(children: [UIMenu(options: .displayInline, children: items)] + suggestedActions)
        }
    }
}

/// The text view behind `StepTextView`: sizes itself for a width with the exclusion in place and
/// draws a capsule behind each temperature.
final class StepUITextView: UITextView {
    /// Space between the text and the thumbnail beside it, and below it.
    private static let exclusionGap = CGSize(width: 12, height: 8)

    private var exclusion: CGSize?
    private var pillRanges: [NSRange] = []
    private var pillLayers: [CAShapeLayer] = []
    private var laidOutWidth: CGFloat = -1

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: StepUITextView, _) in
            view.updatePills()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(text: NSAttributedString, pills: [NSRange], exclusion: CGSize?) {
        if attributedText != text { attributedText = text }
        pillRanges = pills
        if self.exclusion != exclusion {
            self.exclusion = exclusion
            laidOutWidth = -1
        }
        setNeedsLayout()
    }

    /// The height the text needs at `width`, never less than the thumbnail beside it.
    func height(forWidth width: CGFloat) -> CGFloat {
        prepareContainer(width: width)
        guard let layoutManager = textLayoutManager else { return 0 }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let textHeight = layoutManager.usageBoundsForTextContainer.maxY
        return ceil(max(textHeight, exclusion?.height ?? 0))
    }

    private func prepareContainer(width: CGFloat) {
        guard width != laidOutWidth else { return }
        laidOutWidth = width
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        textContainer.exclusionPaths = exclusion.map { size in
            let gap = Self.exclusionGap
            return [UIBezierPath(rect: CGRect(x: width - size.width - gap.width, y: 0, width: size.width + gap.width, height: size.height + gap.height))]
        } ?? []
    }

    override func layoutSubviews() {
        prepareContainer(width: bounds.width)
        super.layoutSubviews()
        updatePills()
    }

    /// One capsule behind each line segment of each temperature, under the text.
    private func updatePills() {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        var rects: [CGRect] = []
        for range in pillRanges {
            guard let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { continue }
            layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
                rects.append(rect.insetBy(dx: 0, dy: 1))
                return true
            }
        }
        while pillLayers.count < rects.count {
            let pill = CAShapeLayer()
            layer.insertSublayer(pill, at: 0)
            pillLayers.append(pill)
        }
        while pillLayers.count > rects.count {
            pillLayers.removeLast().removeFromSuperlayer()
        }
        let fill = (tintColor ?? .tintColor).withAlphaComponent(0.16).resolvedColor(with: traitCollection).cgColor
        for (pill, rect) in zip(pillLayers, rects) {
            pill.frame = bounds
            pill.path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).cgPath
            pill.fillColor = fill
        }
    }
}
