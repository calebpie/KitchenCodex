import Foundation

/// How durations read when formatted.
public enum DurationNameStyle: String, Hashable, Sendable, Codable, CaseIterable {
    /// "12 min", "1 hr 30 min", "1½ hr", "8–10 min": the pill in a recipe step.
    case abbreviated
    /// "12 minutes", "1 hour 30 minutes", "8 to 10 minutes": whole words and no fraction glyphs or
    /// dashes, for VoiceOver to read aloud.
    case full
}

extension DurationUnit {
    /// The unit's name for display: "sec", "min", "hr" and "day"/"days" abbreviated; the full names
    /// take an "s" when `plural` is true.
    public func name(style: DurationNameStyle, plural: Bool) -> String {
        switch style {
        case .abbreviated:
            return switch self {
            case .seconds: "sec"
            case .minutes: "min"
            case .hours: "hr"
            case .days: plural ? "days" : "day"
            }
        case .full:
            let singular = switch self {
            case .seconds: "second"
            case .minutes: "minute"
            case .hours: "hour"
            case .days: "day"
            }
            return plural ? singular + "s" : singular
        }
    }
}

extension CookingDuration {
    /// The duration broken into whole hours, whole minutes and the seconds left: "1 hr 30 min",
    /// "12 min", "1 min 30 sec", "0 sec"; in the full style "1 hour 30 minutes". Days are never
    /// used: 48 hours reads "48 hr".
    ///
    /// A duration the parser read formats as the recipe wrote it instead; see
    /// ``ParsedDuration/formatted(style:)``.
    public func formatted(style: DurationNameStyle = .abbreviated) -> String {
        ParsedDuration.Spelling.canonical.format(self, style: style)
    }
}

extension ParsedDuration {
    /// The duration as the cook reads it, following the recipe's own spelling: "12 minutes" is
    /// "12 min", "90 minutes" stays "90 min", "1 hour 30 minutes" is "1 hr 30 min", "1½ hours" is
    /// "1½ hr", "8–10 minutes" is "8–10 min", "45 minutes to 1 hour" is "45 min–1 hr", and
    /// "overnight" stays "overnight". A fraction with no single glyph is broken into smaller
    /// units: "1.3 hours" is "1 hr 18 min".
    ///
    /// The full style spells every unit out and never uses a fraction or a dash, so VoiceOver
    /// reads it well: "12 minutes", "1 hour 30 minutes" (also for "1½ hours"), "8 to 10 minutes",
    /// "30 minutes" for "half an hour".
    public func formatted(style: DurationNameStyle = .abbreviated) -> String {
        guard let upper, let upperSpelling else {
            return lowerSpelling.format(lower, style: style)
        }
        let joint = style == .full ? " to " : "–"
        // Two numbers in one unit share it: "8–10 min", "8 to 10 minutes", "1–1½ hr".
        if case .single(let unit) = lowerSpelling, case .single(let upperUnit) = upperSpelling, unit == upperUnit {
            let low = lower.seconds / unit.seconds
            let high = upper.seconds / unit.seconds
            if DurationFormatting.readsAsOneTerm(low, style: style), DurationFormatting.readsAsOneTerm(high, style: style) {
                let name = unit.name(style: style, plural: DurationFormatting.isPlural(high, style: style))
                return "\(low.mixedNumberString)\(joint)\(high.mixedNumberString) \(name)"
            }
        }
        return lowerSpelling.format(lower, style: style) + joint + upperSpelling.format(upper, style: style)
    }
}

extension ParsedDuration.Spelling {
    /// `duration` written this way.
    func format(_ duration: CookingDuration, style: DurationNameStyle) -> String {
        switch self {
        case .overnight:
            return "overnight"
        case .compound(let largest):
            return DurationFormatting.decomposed(duration.seconds, from: largest, style: style)
        case .single(let unit):
            let value = duration.seconds / unit.seconds
            if DurationFormatting.readsAsOneTerm(value, style: style) {
                return DurationFormatting.term(value, unit, style: style)
            }
            return DurationFormatting.decomposed(duration.seconds, from: unit, style: style)
        }
    }
}

enum DurationFormatting {
    /// Whether `value` in one unit can stand alone: abbreviated, a whole number or one with a
    /// vulgar-fraction glyph ("1½"); in full, whole numbers only.
    static func readsAsOneTerm(_ value: Rational, style: DurationNameStyle) -> Bool {
        switch style {
        case .abbreviated: !value.mixedNumberString.contains("/")
        case .full: value.isWhole
        }
    }

    /// Whole numbers above one are plural, as are zero and decimals ("0.5 seconds"); "½ hour" and
    /// "1 hour" are singular.
    static func isPlural(_ value: Rational, style: DurationNameStyle) -> Bool {
        if style == .full, !value.isWhole { return value != 1 }
        return value.isZero || value.magnitude > 1
    }

    /// One number and its unit: "1½ hr", "90 min", "2 days"; in full "90 minutes", "0.5 seconds".
    static func term(_ value: Rational, _ unit: DurationUnit, style: DurationNameStyle) -> String {
        let number: String
        switch style {
        case .abbreviated:
            number = value.mixedNumberString
        case .full:
            number = value.isWhole ? "\(value.numerator)" : value.decimalString(maximumFractionDigits: 2)
        }
        return "\(number) \(unit.name(style: style, plural: isPlural(value, style: style)))"
    }

    /// `seconds` as whole numbers of `largest` and each smaller unit, seconds taking whatever is
    /// left: 5400 from hours is "1 hr 30 min", 90 from minutes is "1 min 30 sec", 90 from hours
    /// is also "1 min 30 sec", and zero is "0 sec".
    static func decomposed(_ seconds: Rational, from largest: DurationUnit, style: DurationNameStyle) -> String {
        var remaining = seconds.magnitude
        var parts: [String] = []
        for unit in DurationUnit.allCases.reversed() where unit <= largest && unit != .seconds {
            let whole = (remaining / unit.seconds).floor
            guard whole > 0 else { continue }
            parts.append(term(Rational(whole), unit, style: style))
            remaining -= Rational(whole) * unit.seconds
        }
        if !remaining.isZero || parts.isEmpty {
            parts.append(term(remaining, .seconds, style: style))
        }
        return (seconds.isNegative ? "-" : "") + parts.joined(separator: " ")
    }
}
