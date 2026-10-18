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
/// - **Note forms** (slice 7, its own flag). A stored note without a form takes the form a fresh
///   reading gives when the fresh note has the same words, else parenthetical, which is how such
///   notes read until now. Nothing else on the line changes. The lasagne's "plus extra (for
///   kneading)" becomes a clause and reads "all-purpose flour, plus extra (for kneading)".
/// - **Approximate equivalents** (slice 8, its own flag). A stored item that starts with an
///   approximate equivalent the parser now drops ("(about 2 kg) russet or Yukon Gold potatoes")
///   takes the fresh item, and fluid ounces where the dropped measure now tells them apart, when
///   the item without it is the fresh item and nothing else on the line reads differently. The
///   roast potatoes read "4 lb russet or Yukon Gold potatoes".
enum IngredientReread {
    static let defaultsKey = "ingredients.reread.notesAndLiquidOunces"
    static let noteFormsKey = "ingredients.reread.noteForms"
    static let approximateEquivalentsKey = "ingredients.reread.approximateEquivalents"
    private static let logger = Logger(subsystem: "com.calebpietrafesa.RecipeCodex", category: "store")

    /// Runs each pass once per install, in order; later launches return at once.
    static func runOnce(in context: ModelContext, defaults: UserDefaults = .standard) {
        let rereadsLines = !defaults.bool(forKey: defaultsKey)
        let setsNoteForms = !defaults.bool(forKey: noteFormsKey)
        let dropsEquivalents = !defaults.bool(forKey: approximateEquivalentsKey)
        guard rereadsLines || setsNoteForms || dropsEquivalents else { return }
        guard let ingredients = try? context.fetch(FetchDescriptor<Ingredient>()) else { return }
        if rereadsLines {
            var fluidOunces = 0
            var notes = 0
            for ingredient in ingredients {
                switch reread(ingredient) {
                case .fluidOunces: fluidOunces += 1
                case .note: notes += 1
                case nil: break
                }
            }
            logger.notice("Re-read \(ingredients.count) stored ingredients: \(fluidOunces) now fluid ounces, \(notes) with a note split out")
        }
        if setsNoteForms {
            var clauses = 0
            var parentheticals = 0
            for ingredient in ingredients {
                switch setNoteForm(ingredient) {
                case .clause?: clauses += 1
                case .parenthetical?: parentheticals += 1
                case nil: break
                }
            }
            logger.notice("Set the form of \(clauses + parentheticals) stored notes: \(clauses) clauses, \(parentheticals) parentheticals")
        }
        if dropsEquivalents {
            var items = 0
            var fluidOunces = 0
            for ingredient in ingredients {
                switch dropApproximateEquivalent(ingredient) {
                case .item?: items += 1
                case .itemAndFluidOunces?: items += 1; fluidOunces += 1
                case nil: break
                }
            }
            logger.notice("Dropped an approximate equivalent from \(items) of \(ingredients.count) stored items, \(fluidOunces) now fluid ounces")
        }
        if context.hasChanges { try? context.save() }
        defaults.set(true, forKey: defaultsKey)
        defaults.set(true, forKey: noteFormsKey)
        defaults.set(true, forKey: approximateEquivalentsKey)
    }

    enum EquivalentChange: Equatable {
        case item, itemAndFluidOunces
    }

    /// Takes the fresh item for a stored item that starts with an approximate equivalent, when
    /// the item without it is what a fresh reading of the line gives and the amount, preparation,
    /// note, produce equivalent and optional flag read the same. The unit may only go from ounces
    /// to fluid ounces, which the dropped measure now decides ("5 ounces (about 150 ml) juice").
    @discardableResult
    static func dropApproximateEquivalent(_ ingredient: Ingredient) -> EquivalentChange? {
        guard let stripped = IngredientParser.removingLeadingApproximateEquivalent(from: ingredient.item) else { return nil }
        let parsed = IngredientParser.parse(ingredient.rawText)
        let storedQuantity = ingredient.quantityNumerator.map { Rational($0, max(1, ingredient.quantityDenominator ?? 1)) }
        let storedEquivalent = ingredient.equivalentCountNumerator.map { Rational($0, max(1, ingredient.equivalentCountDenominator ?? 1)) }
        let becomesFluid = ingredient.unit == CookingUnit.ounce.rawValue && parsed.unit == .fluidOunce
        guard parsed.item == stripped,
              parsed.quantity == storedQuantity,
              parsed.unit?.rawValue == ingredient.unit || becomesFluid,
              parsed.preparation == ingredient.preparation,
              parsed.note == ingredient.note,
              ingredient.note == nil || parsed.noteForm?.rawValue == ingredient.noteForm,
              parsed.equivalent?.count == storedEquivalent,
              parsed.equivalent?.item == ingredient.equivalentItem,
              parsed.isOptional == ingredient.isOptional
        else { return nil }
        ingredient.item = parsed.item
        if becomesFluid { ingredient.unit = CookingUnit.fluidOunce.rawValue }
        return becomesFluid ? .itemAndFluidOunces : .item
    }

    /// Gives a stored note without a form the form a fresh reading of its line finds, when the fresh
    /// note holds the same words; otherwise parenthetical. Touches nothing else on the line.
    @discardableResult
    static func setNoteForm(_ ingredient: Ingredient) -> NoteForm? {
        guard let note = ingredient.note, !note.isEmpty, ingredient.noteForm == nil else { return nil }
        let parsed = IngredientParser.parse(ingredient.rawText)
        var form = NoteForm.parenthetical
        if let fresh = parsed.note, words(fresh) == words(note), let freshForm = parsed.noteForm {
            form = freshForm
        }
        ingredient.noteForm = form.rawValue
        return form
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
