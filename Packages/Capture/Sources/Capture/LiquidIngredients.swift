import Foundation
import Units

/// Ingredient words for liquids, so "ounces" of them read as fluid ounces (04 §5.1 Liquid ounces).
///
/// An ingredient is a liquid when its head noun, the last word of the item once qualifiers such as
/// "for frying" or "(or water)" are cut, is a liquid word: "freshly squeezed orange juice", "chicken
/// or vegetable stock", "dry white wine". Compounds whose head is something else stay solid ("cream
/// cheese", "milk chocolate", "oil-packed tuna", "tuna in oil"), and a few solid foods named after a
/// liquid are listed as exceptions ("sour cream", "ice cream").
public enum LiquidIngredients {
    /// Head nouns that name a liquid.
    static let words: Set<String> = [
        // Water and stocks
        "water", "stock", "stocks", "broth", "broths", "bouillon", "consommé", "consomme", "dashi", "brine",
        "liquid", "court-bouillon",
        // Dairy and plant milks
        "milk", "buttermilk", "cream", "half-and-half", "kefir", "whey", "eggnog",
        // Juices and soft drinks
        "juice", "juices", "nectar", "cider", "lemonade", "soda", "seltzer", "kombucha", "coffee", "espresso", "tea",
        // Fats that pour
        "oil", "oils",
        // Wine, beer and spirits
        "wine", "wines", "beer", "beers", "lager", "ale", "stout", "porter", "sake", "mirin", "shaoxing", "vermouth",
        "sherry", "port", "madeira", "marsala", "brandy", "cognac", "armagnac", "calvados", "rum", "vodka", "gin",
        "whiskey", "whisky", "bourbon", "tequila", "mezcal", "liqueur", "amaretto", "kirsch", "grappa", "champagne",
        "prosecco", "cava",
        // Vinegars, syrups and sauces
        "vinegar", "vinegars", "syrup", "syrups", "honey", "molasses", "treacle", "sauce", "sauces", "tamari",
        "worcestershire", "sriracha", "marinade", "dressing",
    ]

    /// Two-word heads that name a liquid even though the last word alone does not.
    static let phrases: [String] = ["half and half", "agave nectar", "simple syrup"]

    /// Foods named after a liquid that are not poured.
    static let exceptions: [String] = ["sour cream", "ice cream", "clotted cream", "whipped cream", "cream of tartar"]

    /// Qualifiers that follow the head noun and are cut before it is read: "olive oil for frying",
    /// "water plus more as needed", "stock such as homemade".
    private static let trailingQualifier = #"\s+(for|plus|such as|like|from|in|to|as|if|at|about|or more|preferably)\b.*$"#

    /// Whether `item` names a liquid.
    public static func isLiquid(_ item: String) -> Bool {
        let text = item.lowercased()
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: trailingQualifier, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[.,;:!*]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return false }
        if exceptions.contains(where: { text == $0 || text.hasSuffix(" \($0)") }) { return false }
        if phrases.contains(where: { text == $0 || text.hasSuffix(" \($0)") }) { return true }
        guard let head = text.split(separator: " ").last else { return false }
        return words.contains(String(head))
    }

    /// Whether "ounces" in a line means fluid ounces. A metric (or US) volume in parentheses says
    /// so ("5 ounces (142 ml) orange juice"); a weight in parentheses says not ("4 ounces (113 g)
    /// butter"); otherwise the item decides.
    public static func ouncesAreFluid(item: String, equivalent: CookingUnit?) -> Bool {
        if let equivalent {
            if equivalent.isVolume { return true }
            if equivalent.isMass { return false }
        }
        return isLiquid(item)
    }
}
