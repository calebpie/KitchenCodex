import Capture
import Foundation
import OSLog
import RecipeModel
import SwiftData
import Units

/// A one-time re-read of stored ingredient lines, run at the first launch after the parser learned
/// notes and produce equivalents (04 §5.1 Ingredient lines). The parser runs at import and on edit,
/// so recipes saved earlier keep their old reading until then:
///
/// - **Liquid ounces.** A line whose text says "ounce" or "oz" without "fl", stored as ounces of
///   weight, whose item is a liquid, takes the parser's fluid ounces, item, preparation, note and
///   equivalent (04 §5.1 Liquid ounces): the short ribs' "5 ounces (142 ml) orange juice" reads
///   5 fl oz instead of 140 g. The amount is never changed.
/// - **Notes.** A line with no note whose fresh reading finds one takes the new item, preparation,
///   note and equivalent, but only when those hold the same words as the stored item and
///   preparation, so the re-read moves words and never rewrites a line some other parser change
///   would read differently.
enum IngredientReread {
    static let defaultsKey = "ingredients.reread.notesAndLiquidOunces"
    private static let logger = Logger(subsystem: "com.calebpietrafesa.RecipeCodex", category: "store")

    /// Re-reads every stored ingredient once per install; later launches return at once.
    static func runOnce(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: defaultsKey) else { return }
        guard let ingredients = try? context.fetch(FetchDescriptor<Ingredient>()) else { return }
        var fluidOunces = 0
        var notes = 0
        for ingredient in ingredients {
            switch reread(ingredient) {
            case .fluidOunces: fluidOunces += 1
            case .note: notes += 1
            case nil: break
            }
        }
        if context.hasChanges { try? context.save() }
        defaults.set(true, forKey: defaultsKey)
        logger.notice("Re-read \(ingredients.count) stored ingredients: \(fluidOunces) now fluid ounces, \(notes) with a note split out")
    }

    enum Change: Equatable {
        case fluidOunces, note
    }

    /// Updates one ingredient from a fresh reading of its `rawText`, and says what changed.
    @discardableResult
    static func reread(_ ingredient: Ingredient) -> Change? {
        let parsed = IngredientParser.parse(ingredient.rawText)
        if saysWeightOunces(ingredient.rawText), ingredient.unit == CookingUnit.ounce.rawValue,
           LiquidIngredients.isLiquid(ingredient.item), parsed.unit == .fluidOunce,
           parsed.quantity == ingredient.quantityNumerator.map({ Rational($0, max(1, ingredient.quantityDenominator ?? 1)) }) {
            ingredient.unit = CookingUnit.fluidOunce.rawValue
            ingredient.setWording(from: parsed)
            return .fluidOunces
        }
        if ingredient.note == nil, let note = parsed.note,
           words(ingredient.item, ingredient.preparation) == words(parsed.item, parsed.preparation, note) {
            ingredient.setWording(from: parsed)
            return .note
        }
        return nil
    }

    /// "5 ounces (142 ml) orange juice", "8 oz milk"; not "8 fl oz", "8 fluid ounces".
    static func saysWeightOunces(_ text: String) -> Bool {
        text.range(of: #"\b(oz|ounces?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            && text.range(of: #"\b(fl\.?|fluid)\s*(oz|ounces?)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
    }

    /// The letters and digits of the parts, so "1/2 -inch strips (ask your butcher)" and
    /// "1/2-inch strips" + "ask your butcher" compare equal.
    private static func words(_ parts: String?...) -> String {
        parts.compactMap(\.self).joined().lowercased().filter { !$0.isWhitespace && !"(),;".contains($0) }
    }
}
