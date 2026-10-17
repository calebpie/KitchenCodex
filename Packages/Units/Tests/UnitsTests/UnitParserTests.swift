import Testing
@testable import Units

@Suite("Unit parser")
struct UnitParserTests {
    @Test(arguments: [
        ("Tbsp", CookingUnit.tablespoon),
        ("tablespoons", .tablespoon),
        ("T", .tablespoon),
        ("TBSP.", .tablespoon),
        ("Tbs", .tablespoon),
        ("t", .teaspoon),
        ("tsp", .teaspoon),
        ("Teaspoon", .teaspoon),
        ("TSP", .teaspoon),
        ("g", .gram),
        ("G", .gram),
        ("grams", .gram),
        ("gm", .gram),
        ("fl. oz.", .fluidOunce),
        ("fl oz", .fluidOunce),
        ("FL OZ", .fluidOunce),
        ("fluid ounces", .fluidOunce),
        ("floz", .fluidOunce),
        ("c", .cup),
        ("C", .cup),
        ("Cups", .cup),
        ("ml", .milliliter),
        ("mL", .milliliter),
        ("ML", .milliliter),
        ("millilitres", .milliliter),
        ("l", .liter),
        ("L", .liter),
        ("liters", .liter),
        ("litre", .liter),
        ("lbs", .pound),
        ("lb.", .pound),
        ("Pounds", .pound),
        ("oz", .ounce),
        ("ounces", .ounce),
        ("kg", .kilogram),
        ("kilos", .kilogram),
        ("pt", .pint),
        ("pints", .pint),
        ("qt.", .quart),
        ("Quarts", .quart),
        ("gal", .gallon),
        ("gallons", .gallon),
        ("pinch", .pinch),
        ("pinches", .pinch),
        ("dash", .dash),
        ("dashes", .dash),
        ("to taste", .toTaste),
        ("To  Taste", .toTaste),
        ("piece", .piece),
        ("pcs", .piece),
        ("each", .piece),
        ("  cups  ", .cup),
        ("tbsp...", .tablespoon),
        ("fl.oz", .fluidOunce),
    ])
    func recognizes(text: String, unit: CookingUnit) {
        #expect(UnitParser.parse(text) == unit)
        #expect(UnitParser().parse(text) == unit)
        #expect(CookingUnit(parsing: text) == unit)
    }

    @Test(arguments: ["", " ", ".", "handful", "cupsful", "tb", "x", "12", "cup of", "tsp tbsp", "smidgen", "°F"])
    func rejectsUnknownStrings(text: String) {
        #expect(UnitParser.parse(text) == nil)
        #expect(CookingUnit(parsing: text) == nil)
    }

    @Test func singleLettersFollowCookbookConvention() {
        #expect(UnitParser.parse("T") == .tablespoon)
        #expect(UnitParser.parse("t") == .teaspoon)
        #expect(UnitParser.parse(" T ") == .tablespoon)
        #expect(UnitParser.parse("T.") == .tablespoon)
    }

    @Test func rawValuesAndFullNamesRoundTrip() {
        for unit in CookingUnit.allCases {
            #expect(UnitParser.parse(unit.name(style: .full, plural: false)) == unit, "\(unit)")
            #expect(UnitParser.parse(unit.name(style: .full, plural: true)) == unit, "\(unit)")
            let abbreviated = unit.name(style: .abbreviated, plural: false)
            if !abbreviated.isEmpty {
                #expect(UnitParser.parse(abbreviated) == unit, "\(unit)")
            }
        }
    }

    @Test func rawValuesAreUnchanged() {
        let expected = ["teaspoon", "tablespoon", "fluidOunce", "cup", "pint", "quart", "gallon", "milliliter", "liter",
                        "ounce", "pound", "gram", "kilogram", "piece", "pinch", "dash", "toTaste"]
        #expect(CookingUnit.allCases.map(\.rawValue) == expected)
    }
}
