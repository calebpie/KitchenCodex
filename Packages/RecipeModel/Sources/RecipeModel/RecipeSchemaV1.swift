import Foundation
import SwiftData

/// Schema version 1, defined in Docs/Planning/02-Flows-and-Architecture.md §4.2.
///
/// CloudKit rules (every relationship optional with an inverse, no unique constraints,
/// defaults on every non-optional attribute, images in external storage) are enforced
/// by `SchemaTests` in this package.
///
/// Models live inside this enum so that a future `RecipeSchemaV2` can coexist with it during a
/// migration. Top-level typealiases below give the rest of the app the plain names.
public enum RecipeSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            // Library
            Book.self, BookSection.self, BookEntry.self,
            Recipe.self, RecipeVersion.self, Ingredient.self, Step.self,
            RecipeLink.self, Tag.self, CookSession.self, SourceInfo.self,
            NutritionEstimate.self, RecipeImage.self, RecipeCollection.self,
            Reference.self, ReferenceSection.self,
            // Planning
            Event.self, Guest.self, EventMenu.self, Slot.self, Candidate.self,
            Pairing.self, ShoppingList.self, ShoppingItem.self, Schedule.self, ScheduleTask.self,
            // Kitchen
            Kitchen.self, Tool.self, PantryItem.self, Source.self, BeverageItem.self, UserProfile.self,
        ]
    }
}

/// Migration plan. Empty until schema v2 exists.
public enum RecipeMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [RecipeSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

// MARK: - Current-version aliases

public typealias Book = RecipeSchemaV1.Book
public typealias BookSection = RecipeSchemaV1.BookSection
public typealias BookEntry = RecipeSchemaV1.BookEntry
public typealias Recipe = RecipeSchemaV1.Recipe
public typealias RecipeVersion = RecipeSchemaV1.RecipeVersion
public typealias Ingredient = RecipeSchemaV1.Ingredient
public typealias Step = RecipeSchemaV1.Step
public typealias RecipeLink = RecipeSchemaV1.RecipeLink
public typealias Tag = RecipeSchemaV1.Tag
public typealias CookSession = RecipeSchemaV1.CookSession
public typealias SourceInfo = RecipeSchemaV1.SourceInfo
public typealias NutritionEstimate = RecipeSchemaV1.NutritionEstimate
public typealias RecipeImage = RecipeSchemaV1.RecipeImage
public typealias RecipeCollection = RecipeSchemaV1.RecipeCollection
public typealias Reference = RecipeSchemaV1.Reference
public typealias ReferenceSection = RecipeSchemaV1.ReferenceSection
public typealias Event = RecipeSchemaV1.Event
public typealias Guest = RecipeSchemaV1.Guest
/// The planning doc calls this `Menu`; the class is `EventMenu` to avoid clashing with SwiftUI's `Menu`.
public typealias EventMenu = RecipeSchemaV1.EventMenu
public typealias Slot = RecipeSchemaV1.Slot
public typealias Candidate = RecipeSchemaV1.Candidate
public typealias Pairing = RecipeSchemaV1.Pairing
public typealias ShoppingList = RecipeSchemaV1.ShoppingList
public typealias ShoppingItem = RecipeSchemaV1.ShoppingItem
public typealias Schedule = RecipeSchemaV1.Schedule
/// The planning doc calls this `Task`; the class is `ScheduleTask` to avoid clashing with Swift concurrency's `Task`.
public typealias ScheduleTask = RecipeSchemaV1.ScheduleTask
public typealias Kitchen = RecipeSchemaV1.Kitchen
public typealias Tool = RecipeSchemaV1.Tool
public typealias PantryItem = RecipeSchemaV1.PantryItem
public typealias Source = RecipeSchemaV1.Source
public typealias BeverageItem = RecipeSchemaV1.BeverageItem
public typealias UserProfile = RecipeSchemaV1.UserProfile
