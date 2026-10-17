import Foundation
import SwiftData

extension RecipeSchemaV1 {
    /// A dinner: who, when, where.
    @Model
    public final class Event {
        public var id: UUID = UUID()
        public var name: String = ""
        public var date: Date = Date.now
        public var arrivalTime: Date?
        public var seatingTime: Date?
        public var guestCount: Int = 0
        public var status: EventStatus = EventStatus.planning
        public var notes: String = ""

        public var kitchen: Kitchen?
        @Relationship(deleteRule: .nullify, inverse: \Guest.events) public var guests: [Guest]?
        @Relationship(deleteRule: .cascade, inverse: \EventMenu.event) public var menu: EventMenu?
        @Relationship(deleteRule: .cascade, inverse: \ShoppingList.event) public var shoppingList: ShoppingList?
        @Relationship(deleteRule: .cascade, inverse: \Schedule.event) public var schedule: Schedule?
        @Relationship(deleteRule: .nullify, inverse: \CookSession.event) public var cookSessions: [CookSession]?

        public init(name: String = "", date: Date = .now, guestCount: Int = 0) {
            self.name = name
            self.date = date
            self.guestCount = guestCount
        }
    }

    /// A guest profile, reused across events.
    @Model
    public final class Guest {
        public var id: UUID = UUID()
        public var name: String = ""
        public var restrictions: [String] = []
        public var preferences: String = ""
        public var notes: String = ""

        public var events: [Event]?

        public init(name: String = "", restrictions: [String] = []) {
            self.name = name
            self.restrictions = restrictions
        }
    }

    /// The menu for one event: course slots holding candidate recipes.
    @Model
    public final class EventMenu {
        public var id: UUID = UUID()
        public var name: String = ""
        public var notes: String = ""

        public var event: Event?
        @Relationship(deleteRule: .cascade, inverse: \Slot.menu) public var slots: [Slot]?

        public init(name: String = "") {
            self.name = name
        }
    }

    /// A course slot (Starter, Main, Sides, Dessert, Drinks, or custom).
    @Model
    public final class Slot {
        public var id: UUID = UUID()
        public var name: String = ""
        public var sortOrder: Int = 0

        public var menu: EventMenu?
        @Relationship(deleteRule: .cascade, inverse: \Candidate.slot) public var candidates: [Candidate]?

        public init(name: String = "", sortOrder: Int = 0) {
            self.name = name
            self.sortOrder = sortOrder
        }
    }

    /// A recipe considered for a slot, with its event-specific settings.
    @Model
    public final class Candidate {
        public var id: UUID = UUID()
        public var servings: Int = 0
        public var donenessTarget: String?
        public var isFinalized: Bool = false
        public var notes: String = ""

        public var slot: Slot?
        public var recipe: Recipe?

        public init(servings: Int = 0) {
            self.servings = servings
        }
    }

    /// Aggregated shopping for an event.
    @Model
    public final class ShoppingList {
        public var id: UUID = UUID()
        public var name: String = ""
        public var createdAt: Date = Date.now

        public var event: Event?
        @Relationship(deleteRule: .cascade, inverse: \ShoppingItem.list) public var items: [ShoppingItem]?

        public init(name: String = "") {
            self.name = name
        }
    }

    /// One line on the shopping list. Check-offs sync; `sourceRecipeIDs` says which recipes need it.
    @Model
    public final class ShoppingItem {
        public var id: UUID = UUID()
        public var normalizedIngredient: String = ""
        public var quantityText: String = ""
        public var stop: String?
        public var section: String?
        public var isChecked: Bool = false
        public var isInPantry: Bool = false
        public var sortOrder: Int = 0
        public var sourceRecipeIDs: [UUID] = []

        public var list: ShoppingList?

        public init(normalizedIngredient: String = "", quantityText: String = "") {
            self.normalizedIngredient = normalizedIngredient
            self.quantityText = quantityText
        }
    }

    /// The workback schedule for an event.
    @Model
    public final class Schedule {
        public var id: UUID = UUID()
        public var createdAt: Date = Date.now
        public var generatedAt: Date?
        public var concurrencyLimit: Int = 2

        public var event: Event?
        @Relationship(deleteRule: .cascade, inverse: \ScheduleTask.schedule) public var tasks: [ScheduleTask]?

        public init(concurrencyLimit: Int = 2) {
            self.concurrencyLimit = concurrencyLimit
        }
    }

    /// One placed task on the timeline. Dependencies and resources are stored by ID so that
    /// the Scheduler package can work on plain values without touching SwiftData.
    @Model
    public final class ScheduleTask {
        public var id: UUID = UUID()
        public var title: String = ""
        public var start: Date?
        public var durationMinutes: Int = 0
        public var kind: ScheduleTaskKind = ScheduleTaskKind.active
        public var dependencyIDs: [UUID] = []
        public var resources: [String] = []
        public var isLocked: Bool = false
        public var isDone: Bool = false
        public var sortOrder: Int = 0

        public var schedule: Schedule?
        public var recipe: Recipe?
        public var step: Step?

        public init(title: String = "", durationMinutes: Int = 0, kind: ScheduleTaskKind = .active) {
            self.title = title
            self.durationMinutes = durationMinutes
            self.kind = kind
        }
    }
}
