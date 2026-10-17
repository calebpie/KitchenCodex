import Foundation
import SwiftData

extension RecipeSchemaV1 {
    /// A place you cook. Most people have one; hosts sometimes cook in a friend's.
    @Model
    public final class Kitchen {
        public var id: UUID = UUID()
        public var name: String = "Home"
        public var isDefault: Bool = false
        public var notes: String = ""

        @Relationship(deleteRule: .cascade, inverse: \Tool.kitchen) public var tools: [Tool]?
        @Relationship(deleteRule: .cascade, inverse: \PantryItem.kitchen) public var pantryItems: [PantryItem]?
        @Relationship(deleteRule: .nullify, inverse: \Event.kitchen) public var events: [Event]?

        public init(name: String = "Home", isDefault: Bool = false) {
            self.name = name
            self.isDefault = isDefault
        }
    }

    /// Equipment in a kitchen. `type` is a key into the KnowledgeBase equipment taxonomy.
    @Model
    public final class Tool {
        public var id: UUID = UUID()
        public var type: String = ""
        public var name: String = ""
        public var count: Int = 1
        public var capacityText: String?

        public var kitchen: Kitchen?

        public init(type: String = "", name: String = "", count: Int = 1) {
            self.type = type
            self.name = name
            self.count = count
        }
    }

    /// A staple the shopping list can subtract.
    @Model
    public final class PantryItem {
        public var id: UUID = UUID()
        public var item: String = ""
        public var isInStock: Bool = true
        public var isStaple: Bool = true

        public var kitchen: Kitchen?

        public init(item: String = "", isInStock: Bool = true) {
            self.item = item
            self.isInStock = isInStock
        }
    }

    /// The single cook's preferences. One record; synced like everything else.
    @Model
    public final class UserProfile {
        public var id: UUID = UUID()
        public var proficiency: Proficiency = Proficiency.confident
        public var concurrencyLimit: Int = 2
        public var unitPreference: UnitPreference = UnitPreference.us
        public var voiceCommandsEnabled: Bool = false
        public var knuckleModeEnabled: Bool = false
        public var createdAt: Date = Date.now

        public init(proficiency: Proficiency = .confident) {
            self.proficiency = proficiency
        }
    }
}
