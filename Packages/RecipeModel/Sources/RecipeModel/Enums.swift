import Foundation

/// Where a cookbook entry is in the capture pipeline (Flow C).
public enum BookEntryStatus: String, Codable, Sendable, CaseIterable {
    case listed, captured, reviewed
}

/// How one recipe relates to another.
public enum RecipeLinkRole: String, Codable, Sendable, CaseIterable {
    /// A sub-recipe this one is made from ("Pasta Dough, page 84").
    case component
    /// An alternate take on the same dish.
    case variation
    /// Mentioned, not required.
    case reference
}

/// What an attached image is.
public enum RecipeImageRole: String, Codable, Sendable, CaseIterable {
    case photo, pageScan, cookPhoto
}

/// Lifecycle of a dinner.
public enum EventStatus: String, Codable, Sendable, CaseIterable {
    case planning, finalized, inService, completed
}

/// Whether a scheduled task needs the cook's hands.
public enum ScheduleTaskKind: String, Codable, Sendable, CaseIterable {
    case active, passive, cleaning, plating
}

/// Cook proficiency, which scales the scheduler's duration estimates.
public enum Proficiency: String, Codable, Sendable, CaseIterable {
    case learning, confident, advanced
}

/// Preferred display units.
public enum UnitPreference: String, Codable, Sendable, CaseIterable {
    case us, metric
}
