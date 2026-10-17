import Foundation

/// Static culinary knowledge the scheduler, shopping list and service mode consult.
/// Tables here are deterministic and never call a model.
public enum KnowledgeBase {
    /// Bumped whenever a table changes shape so cached derived data can be invalidated.
    public static let tablesVersion = 1
}

/// Where an ingredient is found in a typical grocery store. Drives shopping-list grouping.
public enum StoreSection: String, Sendable, Codable, CaseIterable {
    case produce, meat, seafood, dairy, bakery, deli, frozen, pantry, spices, beverages, other
}

/// Kinds of dish components that share holding behavior.
public enum ComponentType: String, Sendable, Codable, CaseIterable {
    case dough, braise, roast, seared, sauce, soup, salad, grain, vegetable, dessert, bread, drink
}

/// How long a finished component can wait before quality drops, and how.
public struct HoldRule: Sendable, Equatable {
    public enum Method: String, Sendable, Codable {
        case roomTemperature, warm, refrigerated, frozen, mustServeImmediately
    }

    public let component: ComponentType
    public let method: Method
    public let maximumHoldMinutes: Int

    public init(component: ComponentType, method: Method, maximumHoldMinutes: Int) {
        self.component = component
        self.method = method
        self.maximumHoldMinutes = maximumHoldMinutes
    }

    /// The default rule for a component type. Phase 5 refines these and lets recipes override.
    public static func `default`(for component: ComponentType) -> HoldRule {
        switch component {
        case .dough: HoldRule(component: component, method: .refrigerated, maximumHoldMinutes: 72 * 60)
        case .braise, .soup: HoldRule(component: component, method: .warm, maximumHoldMinutes: 120)
        case .roast: HoldRule(component: component, method: .roomTemperature, maximumHoldMinutes: 30)
        case .seared: HoldRule(component: component, method: .mustServeImmediately, maximumHoldMinutes: 5)
        case .sauce: HoldRule(component: component, method: .warm, maximumHoldMinutes: 60)
        case .salad: HoldRule(component: component, method: .refrigerated, maximumHoldMinutes: 20)
        case .grain, .vegetable: HoldRule(component: component, method: .warm, maximumHoldMinutes: 30)
        case .dessert: HoldRule(component: component, method: .refrigerated, maximumHoldMinutes: 24 * 60)
        case .bread: HoldRule(component: component, method: .roomTemperature, maximumHoldMinutes: 4 * 60)
        case .drink: HoldRule(component: component, method: .refrigerated, maximumHoldMinutes: 24 * 60)
        }
    }
}

/// Doneness and food-safety temperatures in degrees Fahrenheit.
public enum Doneness: String, Sendable, Codable, CaseIterable {
    case rare, mediumRare, medium, mediumWell, well
}

public enum Protein: String, Sendable, Codable, CaseIterable {
    case beef, lamb, pork, chicken, turkey, fish, shellfish
}

public enum TemperatureTable {
    /// Target pull temperature for a protein at a doneness, before resting carryover.
    public static func targetFahrenheit(for protein: Protein, doneness: Doneness) -> Int? {
        switch protein {
        case .beef, .lamb:
            switch doneness {
            case .rare: 120
            case .mediumRare: 128
            case .medium: 138
            case .mediumWell: 148
            case .well: 158
            }
        case .pork:
            switch doneness {
            case .rare, .mediumRare: 140
            case .medium: 145
            case .mediumWell: 150
            case .well: 160
            }
        case .chicken, .turkey: 165
        case .fish: doneness == .well ? 145 : 130
        case .shellfish: 145
        }
    }

    /// USDA minimum safe internal temperature, which service mode will never suggest going below.
    public static func foodSafetyMinimumFahrenheit(for protein: Protein) -> Int {
        switch protein {
        case .beef, .lamb, .pork, .fish, .shellfish: 145
        case .chicken, .turkey: 165
        }
    }
}
