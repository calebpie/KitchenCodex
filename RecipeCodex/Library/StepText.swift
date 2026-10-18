import RecipeModel
import SwiftUI
import Units

/// A step's text as written, with each temperature drawn as a pill in the cook's preferred unit
/// (03 §3.3 and §3.12, 04 §5.1 Temperatures): "Roast at 220°C (200°C fan)" reads "Roast at 425°F"
/// for a Fahrenheit cook. The original wording is kept; `StepTemperatureMenu` shows it on long-press.
struct StepText: View {
    let text: String
    let scale: TemperatureScale

    var body: some View {
        StepText.parts(of: text, in: scale).reduce(Text(verbatim: "")) { result, part in
            switch part {
            case let .text(words):
                Text("\(result)\(Text(verbatim: words))")
            case let .temperature(shown, _):
                // Narrow no-break spaces pad the pill without letting a line break inside it.
                Text("\(result)\(Text(verbatim: "\u{202F}\(shown)\u{202F}").customAttribute(TemperaturePill()).foregroundStyle(.tint).fontWeight(.semibold))")
            }
        }
        .textRenderer(TemperaturePillRenderer())
    }

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

/// Long-press on a step with converted temperatures: each one as the recipe wrote it. Steps
/// without one get no menu.
struct StepTemperatureLongPress: ViewModifier {
    let conversions: [(shown: String, original: String)]

    func body(content: Content) -> some View {
        if conversions.isEmpty {
            content
        } else {
            content
                .contentShape(.rect)
                .contextMenu {
                    Section("As Written") {
                        ForEach(conversions.indices, id: \.self) { index in
                            Label("\(conversions[index].shown) is “\(conversions[index].original)”", systemImage: "thermometer.medium")
                        }
                    }
                }
        }
    }
}

/// Marks the run of a `Text` that `TemperaturePillRenderer` draws a capsule behind.
nonisolated struct TemperaturePill: TextAttribute {}

/// Draws a tinted capsule behind each temperature run, then the text.
nonisolated struct TemperaturePillRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[TemperaturePill.self] != nil {
                    let bounds = run.typographicBounds.rect.insetBy(dx: 0, dy: -1)
                    context.fill(Capsule().path(in: bounds), with: .color(Color.accentColor.opacity(0.16)))
                }
                context.draw(run)
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
