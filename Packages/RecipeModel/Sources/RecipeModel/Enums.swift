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
    /// A photo of one step. With a cook session it is the cook's own; without, it came from the source.
    case stepPhoto
}

/// Lifecycle of a dinner.
public enum EventStatus: String, Codable, Sendable, CaseIterable {
    case planning, finalized, inService, completed
}

/// Whether a scheduled task needs the cook's hands.
public enum ScheduleTaskKind: String, Codable, Sendable, CaseIterable {
    case active, passive, cleaning, plating
}

/// Cook proficiency, which scales the scheduler's duration estimates and sets how many hands-on
/// tasks it gives the cook at once (04 §5.1 Proficiency).
public enum Proficiency: String, Codable, Sendable, CaseIterable {
    case learning, confident, advanced, expert

    /// Hands-on tasks the schedule runs at the same time: 1 · 2 · 3 · 4. Passive ones (a roast in
    /// the oven, a dough resting) don't count. Never shown as a setting.
    public var concurrencyLimit: Int {
        switch self {
        case .learning: 1
        case .confident: 2
        case .advanced: 3
        case .expert: 4
        }
    }
}

/// Preferred display units.
public enum UnitPreference: String, Codable, Sendable, CaseIterable {
    case us, metric
}

/// Preferred temperature unit, independent of `UnitPreference` (a metric cook may still bake in °F).
public enum TemperaturePreference: String, Codable, Sendable, CaseIterable {
    case fahrenheit, celsius
}

/// What kind of supplier a `Source` is (03 §3.17 Sources pane).
public enum SourceKind: String, Codable, Sendable, CaseIterable {
    /// A shop you can walk into; a frequented store becomes a shopping stop.
    case store
    /// Ships to you.
    case online
    /// A farm, dairy, fishmonger or maker that sells direct.
    case producer
    case other
}

/// What a `Source` carries, as cookbooks group their Sources pages. A source may carry several.
public enum SourceCategory: String, Codable, Sendable, CaseIterable {
    case equipment, food, drink
}

/// Cellar and bar inventory kinds.
public enum BeverageKind: String, Codable, Sendable, CaseIterable {
    case wine, spirit, liqueur, beer, mixer, nonAlcoholic, other
}

/// The role of a `Pairing` on a course slot; every course can carry a non-alcoholic option.
public enum PairingRole: String, Codable, Sendable, CaseIterable {
    case wine, cocktail, beer, nonAlcoholic, other
}

/// What a `Reference` is (02 §4.2): prose kept beside the recipes it informs.
public enum ReferenceKind: String, Codable, Sendable, CaseIterable {
    /// An essay or article saved from the web (Article markup, no recipe).
    case article
    /// A technique written up on its own: "The Importance of Brown Butter".
    case technique
    /// A cookbook chapter or chapter opener, captured from its pages.
    case chapter
    /// Anything else kept for reference: a clipping, a card, a note from a class.
    case clipping
}

/// How a recipe or reference came into the library, which its source line says (04 §5.1 "Which
/// book"): scanned from a book and page, imported from the web, typed by hand, or imported from
/// another app.
public enum CaptureMethod: String, Codable, Sendable, CaseIterable {
    /// Typed in the editor.
    case manual
    /// A web page, in the app or through the Share Extension.
    case web
    /// A Paprika or Mela export.
    case library
    /// Pages photographed with the document camera.
    case scan
    /// Pages chosen from Photos or Files.
    case photo
}

/// What a scanned page turned out to be once read. A recipe page belongs to its recipe; the others
/// stay with their book (contents and index pages build the punchlist, a Sources page fills Pantry →
/// Sources). Nil on a captured page that has not been read yet (Flow C's background queue).
public enum ScanPageKind: String, Codable, Sendable, CaseIterable {
    case recipe
    case contents
    case index
    case sources
    /// A photo plate: a picture with little or no text.
    case photo
    /// A technique chapter or essay, which becomes a `Reference`.
    case reference
    case other
}
