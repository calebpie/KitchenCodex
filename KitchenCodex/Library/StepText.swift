import Capture
import RecipeModel
import SwiftUI
import UIKit
import Units

/// A step's text as written, with each temperature shown as a pill in the cook's preferred unit
/// (03 §3.3 and §3.12, 04 §5.1 Temperatures): "Roast at 220°C (200°C fan)" reads "Roast at 425°F"
/// for a Fahrenheit cook. Each duration's value is a pill too, in the short form ("1 to 1 1/2 hours"
/// reads "1–1½ hr"), which neither Units nor scaling changes, while the words that qualify it stay as
/// text beside it: "about 10 minutes" reads "about [10 min]", "up to 2 days" "up to [2 days]". The
/// original wording is kept; tapping the pill or the edit menu shows the whole mention as written
/// (04 §5.1 Step pills).
/// The headnote and the notes use the same parts; ingredient lines take only the temperatures.
/// A page pointer in a book's recipe ("Dashi (see page 17)") is a pill too, its printed words
/// unchanged, which opens what the book holds from that page (04 §5.1 "Page pointers").
/// `StepTextView` lays the text out; this type finds the mentions and what they read. A nil
/// scale (Units → As Written) keeps every temperature as written, still marked as a pill.
enum StepText {
    enum Part: Equatable {
        case text(String)
        /// What the pill shows, and the words it stands for.
        case temperature(shown: String, original: String)
        /// What the pill shows ("8–10 min"), what VoiceOver reads ("8 to 10 minutes"), and the
        /// words it stands for.
        case duration(shown: String, spoken: String, original: String)
        /// A page pointer: the words as printed, and where they point.
        case pointer(PagePointer)

        /// Whether the part is a pill rather than plain words.
        var isPill: Bool {
            if case .text = self { false } else { true }
        }
    }

    /// One temperature, duration or page pointer the parsers found, where it sits.
    private enum Mention {
        case temperature(TemperatureMention)
        case duration(DurationMention)
        case pointer(PagePointer)

        /// What the pill covers: a whole temperature, only a duration's number and unit
        /// (`valueRange`), so "at least" in "at least 6 hours" stays as words, and a pointer's
        /// "see page 17".
        var range: Range<String.Index> {
            switch self {
            case let .temperature(mention): mention.range
            case let .duration(mention): mention.valueRange
            case let .pointer(pointer): pointer.range
            }
        }

        var isPointer: Bool {
            if case .pointer = self { true } else { false }
        }
    }

    /// Every temperature `TemperatureParser` finds and, with `includesDurations`, every duration
    /// `DurationParser` finds, in order of where each starts (a temperature first when both start
    /// at once). Day-scale durations written with an article are left out: "once a day" is how
    /// often, and "a day ahead" when, neither a time to count; "2 days" and "3–5 days" stay.
    private static func mentions(in text: String, includesDurations: Bool, includesPointers: Bool = false) -> [Mention] {
        let temperatures = TemperatureParser.mentions(in: text).map(Mention.temperature)
        let durations = includesDurations ? DurationParser.mentions(in: text).filter { !isArticleDay($0) }.map(Mention.duration) : []
        let pointers = includesPointers ? pointersIn(text).map(Mention.pointer) : []
        guard !durations.isEmpty || !pointers.isEmpty else { return temperatures }
        // Stable: the temperatures come first, so they stay first on a tie.
        return (temperatures + durations + pointers).enumerated()
            .sorted { ($0.element.range.lowerBound, $0.offset) < ($1.element.range.lowerBound, $1.offset) }
            .map(\.element)
    }

    /// The page pointers in `text` that become pills: those with a page number, photographs left
    /// out (`PagePointers`).
    static func pointersIn(_ text: String) -> [PagePointer] {
        PagePointers.find(in: text)
    }

    /// "a day", "a day or two": a day or more, written with "a" or "an" rather than a number.
    private static func isArticleDay(_ mention: DurationMention) -> Bool {
        mention.duration.lower >= CookingDuration(1, .days)
            && mention.originalText.range(of: #"^an?\s"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The text split around its pills: every temperature and, with `includesDurations` (steps,
    /// the headnote and the notes), every duration's value, its qualifying words left as text; a
    /// duration pill's original is the whole mention. Mentions that overlap become pills side by
    /// side over the words they share, never one inside another.
    static func parts(of text: String, in scale: TemperatureScale?, includesDurations: Bool = false, includesPointers: Bool = false) -> [Part] {
        var parts: [Part] = []
        var position = text.startIndex
        for mention in mentions(in: text, includesDurations: includesDurations, includesPointers: includesPointers) {
            // A mention inside one already made a pill stays words.
            guard mention.range.lowerBound >= position || !mention.isPointer else { continue }
            if position < mention.range.lowerBound {
                parts.append(.text(String(text[position..<mention.range.lowerBound])))
            }
            switch mention {
            case let .temperature(temperature):
                let shown = scale.map { shown(temperature.temperature, in: $0) } ?? temperature.originalText
                parts.append(.temperature(shown: shown, original: temperature.originalText))
            case let .duration(duration):
                parts.append(.duration(
                    shown: duration.duration.formatted(style: .abbreviated),
                    spoken: duration.duration.formatted(style: .full),
                    original: duration.originalText
                ))
            case let .pointer(pointer):
                parts.append(.pointer(pointer))
            }
            position = max(position, mention.range.upperBound)
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

    /// The step as VoiceOver should read it: temperatures in the preferred unit and durations,
    /// both spelled out, a duration's qualifying words read as written around its value ("at
    /// least 6 hours", "another 8 to 10 minutes"). As Written reads temperatures as the recipe
    /// wrote them.
    static func spoken(_ text: String, in scale: TemperatureScale?) -> String {
        var result = ""
        var position = text.startIndex
        for mention in mentions(in: text, includesDurations: true) {
            if position < mention.range.lowerBound {
                result += text[position..<mention.range.lowerBound]
            } else if position > text.startIndex {
                // Pills side by side read as two values.
                result += " "
            }
            switch mention {
            case let .temperature(temperature):
                result += scale.map { shown(temperature.temperature, in: $0, style: .full) } ?? temperature.originalText
            case let .duration(duration):
                result += duration.duration.formatted(style: .full)
            case let .pointer(pointer):
                result += pointer.text
            }
            position = max(position, mention.range.upperBound)
        }
        return result + text[position...]
    }

    /// Whether `text` mentions a temperature at all.
    static func hasTemperatures(_ text: String) -> Bool {
        !TemperatureParser.mentions(in: text).isEmpty
    }

    /// Pills that differ from what the recipe wrote, as (shown, original) pairs, in order:
    /// converted temperatures and every duration whose short form isn't the recipe's own words.
    static func conversions(in text: String, scale: TemperatureScale?) -> [(shown: String, original: String)] {
        parts(of: text, in: scale, includesDurations: true).compactMap { part in
            switch part {
            case let .temperature(shown, original) where shown != original: (shown, original)
            case let .duration(shown, _, original) where shown != original: (shown, original)
            default: nil
            }
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
/// Dynamic Type, text selection, the temperature and time pills (capsules drawn behind the ranges
/// `StepText` finds) and As Written, which joins the edit menu for a selected pill. A pill is a
/// button (04 §5.1 Step pills): a tap shows a small popover anchored to it with the value shown
/// and the wording as written; a long-press still selects text. A time pill starts no timer yet;
/// timers come with cook mode (Phase 3). The headnote and the notes use the same view, without a
/// thumbnail.
struct StepTextView: View {
    let text: String
    let scale: TemperatureScale?
    /// The thumbnail the text flows around, or nil for none.
    var exclusion: CGSize?
    /// A tap on a page pointer's pill; nil leaves pointers as words (a recipe from no book).
    var onPointer: ((PagePointer) -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var tappedPill: TappedPill?

    /// The pill a tap landed on, and where it sits in this view.
    struct TappedPill: Identifiable, Equatable {
        let id: Int
        let shown: String
        let original: String
        let rect: CGRect
    }

    var body: some View {
        let font = StepTextLayout.font(for: dynamicTypeSize)
        StepTextLayout(text: text, scale: scale, exclusion: exclusion, font: font, showsPointers: onPointer != nil) { pill in
            tappedPill = pill
        } onTapPointer: { pointer in
            onPointer?(pointer)
        }
        // The step number sits on the first line's baseline.
        .alignmentGuide(.firstTextBaseline) { _ in font.ascender }
        .popover(item: $tappedPill, attachmentAnchor: .rect(.rect(tappedPill?.rect ?? .zero))) { pill in
            AsWrittenPopover(shown: pill.shown, original: pill.original)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// What a tapped temperature or time says: the value as shown, then the recipe's own words.
private struct AsWrittenPopover: View {
    let shown: String
    let original: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shown)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
            if original == shown {
                Text("As written.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("As Written")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(original)
                        .font(.body)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(minWidth: 180, idealWidth: 260, maxWidth: 320, alignment: .leading)
    }
}

private struct StepTextLayout: UIViewRepresentable {
    let text: String
    let scale: TemperatureScale?
    let exclusion: CGSize?
    let font: UIFont
    let showsPointers: Bool
    let onTapPill: (StepTextView.TappedPill) -> Void
    let onTapPointer: (PagePointer) -> Void

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
        let (attributed, pills) = Self.attributedText(text, scale: scale, font: font, showsPointers: showsPointers)
        context.coordinator.pills = pills
        view.configure(text: attributed, pills: pills.map(\.range), exclusion: exclusion)
        view.onTapPill = { index, rect in
            guard pills.indices.contains(index) else { return }
            if case let .pointer(pointer) = pills[index].kind {
                onTapPointer(pointer)
            } else {
                onTapPill(.init(id: index, shown: pills[index].shown, original: pills[index].original, rect: rect))
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: StepUITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: view.height(forWidth: width))
    }

    /// The step with each temperature and duration as a semibold, tinted run padded by narrow
    /// no-break spaces, and where each run is, with what the recipe wrote. Pills that touch get a
    /// thin space between them so their capsules stay apart.
    static func attributedText(_ text: String, scale: TemperatureScale?, font: UIFont, showsPointers: Bool) -> (NSAttributedString, [Coordinator.Pill]) {
        let result = NSMutableAttributedString()
        var pills: [Coordinator.Pill] = []
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
        let pill: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: UIColor(Color.accentColor),
        ]
        var previousWasPill = false
        for part in StepText.parts(of: text, in: scale, includesDurations: true, includesPointers: showsPointers) {
            let kind: Coordinator.Pill.Kind
            let shown: String
            let original: String
            switch part {
            case let .text(words):
                result.append(NSAttributedString(string: words, attributes: plain))
                previousWasPill = false
                continue
            case let .temperature(temperature, written):
                (kind, shown, original) = (.temperature, temperature, written)
            case let .duration(duration, _, written):
                (kind, shown, original) = (.duration, duration, written)
            case let .pointer(pointer):
                (kind, shown, original) = (.pointer(pointer), pointer.text, pointer.text)
            }
            if previousWasPill {
                result.append(NSAttributedString(string: "\u{2009}", attributes: plain))
            }
            let run = NSAttributedString(string: "\u{202F}\(shown)\u{202F}", attributes: pill)
            pills.append(.init(kind: kind, range: NSRange(location: result.length, length: run.length), shown: shown, original: original))
            result.append(run)
            previousWasPill = true
        }
        return (result, pills)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        struct Pill {
            enum Kind {
                case temperature, duration
                /// Opens the page; its words are the recipe's own.
                case pointer(PagePointer)

                var systemImage: String {
                    switch self {
                    case .temperature: "thermometer.medium"
                    case .duration: "clock"
                    case .pointer: "book.pages"
                    }
                }
            }

            let kind: Kind
            let range: NSRange
            let shown: String
            let original: String
        }

        var pills: [Pill] = []

        /// A selection that touches a converted temperature or a duration offers it as written.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            let written = pills.filter { $0.shown != $0.original && NSIntersectionRange($0.range, range).length > 0 }
            guard !written.isEmpty else { return nil }
            let items = written.map { pill in
                UIAction(title: "As Written: \(pill.original)", image: UIImage(systemName: pill.kind.systemImage)) { _ in }
            }
            return UIMenu(children: [UIMenu(options: .displayInline, children: items)] + suggestedActions)
        }
    }
}

/// The text view behind `StepTextView`: sizes itself for a width with the exclusion in place,
/// draws a capsule behind each pill, and reports a tap on one.
final class StepUITextView: UITextView {
    /// Space between the text and the thumbnail beside it, and below it.
    private static let exclusionGap = CGSize(width: 12, height: 8)

    /// Called with the pill's index and its capsule's rect when a tap lands on a pill.
    var onTapPill: ((Int, CGRect) -> Void)?

    private var exclusion: CGSize?
    private var pillRanges: [NSRange] = []
    private var pillLayers: [CAShapeLayer] = []
    /// Each capsule's rect with the index of its pill; a pill that wraps has one per line.
    private var pillRects: [(index: Int, rect: CGRect)] = []
    private var laidOutWidth: CGFloat = -1
    private let pillTapDelegate = PillTapDelegate()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: StepUITextView, _) in
            view.updatePills()
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        pillTapDelegate.textView = self
        tap.delegate = pillTapDelegate
        addGestureRecognizer(tap)
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        // A held touch is the text view's long-press, which selects; only a quick one is a tap.
        guard ProcessInfo.processInfo.systemUptime - pillTapDelegate.touchBegan < PillTapDelegate.longestTap,
              let hit = pill(at: recognizer.location(in: self)) else { return }
        onTapPill?(hit.index, hit.rect)
    }

    /// The pill under `point`, with a hit area grown to the 44 pt minimum height.
    fileprivate func pill(at point: CGPoint) -> (index: Int, rect: CGRect)? {
        pillRects.first { _, rect in
            rect.insetBy(dx: -4, dy: -max(4, (44 - rect.height) / 2)).contains(point)
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

    /// One capsule behind each line segment of each pill, under the text.
    private func updatePills() {
        guard let layoutManager = textLayoutManager, let content = layoutManager.textContentManager else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        var rects: [CGRect] = []
        pillRects = []
        for (index, range) in pillRanges.enumerated() {
            guard let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { continue }
            layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
                let capsule = rect.insetBy(dx: 0, dy: 1)
                rects.append(capsule)
                pillRects.append((index, capsule))
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

/// The pill tap's delegate, kept apart from the text view so none of `UITextView`'s own gesture
/// handling is overridden: the tap begins only on a pill, and alongside the text view's taps.
private final class PillTapDelegate: NSObject, UIGestureRecognizerDelegate {
    /// Seconds a touch may be held and still count as a tap.
    static let longestTap: TimeInterval = 0.4

    weak var textView: StepUITextView?
    /// When the current touch began, on the system uptime clock `UITouch` uses.
    private(set) var touchBegan: TimeInterval = 0

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touchBegan = touch.timestamp
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let textView else { return false }
        return textView.pill(at: gestureRecognizer.location(in: textView)) != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Accessibility

extension View {
    /// One element reading `text` with its temperatures spelled out in `scale` and its durations
    /// spelled out ("8 to 10 minutes"), after `prefix` ("Step 2."), with the originals as custom
    /// content and an As Written action that reads them (04 §5.1 Step pills).
    /// A page pointer reads as printed, and each one is an action ("Open page 17") when
    /// `onPointer` is given.
    func pillTextAccessibility(_ text: String, scale: TemperatureScale?, prefix: String? = nil, onPointer: ((PagePointer) -> Void)? = nil) -> some View {
        let originals = StepText.conversions(in: text, scale: scale).map(\.original)
        let pointers = onPointer == nil ? [] : StepText.pointersIn(text)
        return accessibilityElement(children: .ignore)
            .accessibilityLabel([prefix, StepText.spoken(text, in: scale)].compactMap(\.self).joined(separator: " "))
            .accessibilityCustomContent("As Written", originals.joined(separator: "; "), importance: .default)
            .accessibilityActions {
                if !originals.isEmpty {
                    Button("As Written") {
                        AccessibilityNotification.Announcement("As written: \(originals.joined(separator: "; "))").post()
                    }
                }
                ForEach(Array(pointers.enumerated()), id: \.offset) { _, pointer in
                    Button(PagePointerAction.title(for: pointer)) { onPointer?(pointer) }
                }
            }
    }
}

// MARK: - Pills in SwiftUI text

/// Marks a run of SwiftUI `Text` as a temperature, so `TemperaturePillRenderer` draws a capsule
/// behind it: ingredient lines, which stay `Text`, use the same pill as steps.
struct TemperaturePillAttribute: TextAttribute {}

/// Draws a tinted capsule behind each run marked with `TemperaturePillAttribute`, under the text.
struct TemperaturePillRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line where run[TemperaturePillAttribute.self] != nil {
                let rect = run.typographicBounds.rect.insetBy(dx: 0, dy: 1)
                context.fill(Capsule().path(in: rect), with: .color(Color.accentColor.opacity(0.16)))
            }
            for run in line {
                context.draw(run)
            }
        }
    }
}

extension Text {
    /// `text` with each temperature as a pill in `scale` (a semibold, tinted run padded by narrow
    /// no-break spaces, like the step view's), the other words in the primary or secondary color,
    /// for ingredient lines.
    static func withTemperaturePills(_ text: String, scale: TemperatureScale?, isSecondary: Bool = true, pointers: Bool = false) -> Text {
        var result = Text(verbatim: "")
        for part in StepText.parts(of: text, in: scale, includesPointers: pointers) {
            switch part {
            case let .text(words):
                let plain = Text(verbatim: words)
                result = Text("\(result)\(isSecondary ? plain.foregroundStyle(.secondary) : plain)")
            case let .temperature(shown, _):
                let pill = Text(verbatim: "\u{202F}\(shown)\u{202F}")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .customAttribute(TemperaturePillAttribute())
                result = Text("\(result)\(pill)")
            case .duration:
                // Ingredient lines take no time pills (`parts` leaves durations out by default).
                break
            case let .pointer(pointer):
                // A link the line's `openURL` handler takes (`PagePointerAction.url`), drawn as a pill.
                var words = AttributedString("\u{202F}\(pointer.text)\u{202F}")
                words.link = PagePointerAction.url(for: pointer)
                let pill = Text(words)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .customAttribute(TemperaturePillAttribute())
                result = Text("\(result)\(pill)")
            }
        }
        return result
    }
}

/// A page pointer's pill as a link and an accessibility action: the link carries the pointer to the
/// detail's `openURL` handler, never outside the app.
enum PagePointerAction {
    static let scheme = "kitchencodex-pointer"

    static func url(for pointer: PagePointer) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "page"
        components.queryItems = [
            URLQueryItem(name: "pages", value: pointer.pages.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "kind", value: pointer.kind.rawValue),
            URLQueryItem(name: "text", value: pointer.text),
        ] + (pointer.target.map { [URLQueryItem(name: "target", value: $0)] } ?? [])
        return components.url
    }

    /// The pointer a pill's link carries; its range is the words' own.
    static func pointer(from url: URL) -> PagePointer? {
        guard url.scheme == scheme, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let pages = (value("pages") ?? "").split(separator: ",").compactMap { Int($0) }
        guard !pages.isEmpty, let text = value("text") else { return nil }
        return PagePointer(range: text.startIndex..<text.endIndex, text: text, pages: pages,
                           kind: value("kind").flatMap(PageCrossReference.Kind.init(rawValue:)) ?? .recipe, target: value("target"))
    }

    /// "Open page 17", for VoiceOver.
    static func title(for pointer: PagePointer) -> String {
        pointer.pages.count > 1 ? "Open pages \(pointer.pages.map(String.init).joined(separator: " and "))" : "Open page \(pointer.pages[0])"
    }
}
