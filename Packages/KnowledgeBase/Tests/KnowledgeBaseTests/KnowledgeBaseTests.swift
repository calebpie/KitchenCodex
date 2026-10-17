import Testing
@testable import KnowledgeBase

@Suite("Knowledge tables")
struct KnowledgeBaseTests {
    @Test(arguments: ComponentType.allCases)
    func everyComponentHasAHoldRule(component: ComponentType) {
        let rule = HoldRule.default(for: component)
        #expect(rule.component == component)
        #expect(rule.maximumHoldMinutes > 0)
    }

    @Test(arguments: Protein.allCases, Doneness.allCases)
    func everyProteinDonenessPairHasATemperature(protein: Protein, doneness: Doneness) {
        #expect(TemperatureTable.targetFahrenheit(for: protein, doneness: doneness) != nil)
    }

    @Test func poultryMinimumIs165() {
        #expect(TemperatureTable.foodSafetyMinimumFahrenheit(for: .chicken) == 165)
        #expect(TemperatureTable.foodSafetyMinimumFahrenheit(for: .turkey) == 165)
    }

    @Test func donenessTemperaturesIncreaseForBeef() {
        let temps = Doneness.allCases.compactMap { TemperatureTable.targetFahrenheit(for: .beef, doneness: $0) }
        #expect(temps == temps.sorted())
    }
}
