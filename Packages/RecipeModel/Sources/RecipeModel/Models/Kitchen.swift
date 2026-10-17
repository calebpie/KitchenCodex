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
        @Relationship(deleteRule: .nullify, inverse: \Source.kitchen) public var sources: [Source]?
        @Relationship(deleteRule: .cascade, inverse: \BeverageItem.kitchen) public var beverages: [BeverageItem]?
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

    /// A store you frequent or a specialty supplier, as cookbooks list them on a Sources page:
    /// name, phone, website, and what they carry. Frequented stores become shopping stops.
    @Model
    public final class Source {
        public var id: UUID = UUID()
        public var name: String = ""
        public var kind: SourceKind = SourceKind.store
        public var categories: [SourceCategory] = []
        /// What they sell, in the book's own words ("pot de crème molds, lidded terrine molds").
        public var carries: String = ""
        public var phone: String?
        public var url: URL?
        public var address: String?
        public var notes: String = ""
        /// A store you actually shop at; the shopping list offers it as a stop.
        public var isFrequented: Bool = false
        public var addedAt: Date = Date.now

        /// The cookbook whose Sources page this came from, if any.
        public var book: Book?
        /// The kitchen this source is near, for stores; nil for online suppliers.
        public var kitchen: Kitchen?
        public var shoppingItems: [ShoppingItem]?

        public init(name: String = "", kind: SourceKind = .store, categories: [SourceCategory] = []) {
            self.name = name
            self.kind = kind
            self.categories = categories
        }
    }

    /// A bottle in the cellar or on the bar. Pairings read from here to say "on hand" or "to buy".
    @Model
    public final class BeverageItem {
        public var id: UUID = UUID()
        public var kind: BeverageKind = BeverageKind.wine
        public var name: String = ""
        public var producer: String = ""
        public var vintage: Int?
        public var region: String = ""
        /// Grape, style or category ("Chablis", "rye", "sweet vermouth").
        public var style: String = ""
        public var bottles: Int = 1
        public var isOpen: Bool = false
        public var location: String = ""
        public var drinkByNote: String = ""
        public var notes: String = ""
        public var addedAt: Date = Date.now

        public var kitchen: Kitchen?
        public var pairings: [Pairing]?

        public init(kind: BeverageKind = .wine, name: String = "", bottles: Int = 1) {
            self.kind = kind
            self.name = name
            self.bottles = bottles
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
        /// The high-contrast kitchen theme is a toggle, never automatic (03 §3.12).
        public var kitchenThemeEnabled: Bool = false
        /// Raw value of `Intelligence.ModelTier` for menu conversation and pairings; Apple cloud by default (04 §5.1).
        public var heavyReasoningModel: String = "appleCloud"
        public var createdAt: Date = Date.now

        public init(proficiency: Proficiency = .confident) {
            self.proficiency = proficiency
        }
    }
}
