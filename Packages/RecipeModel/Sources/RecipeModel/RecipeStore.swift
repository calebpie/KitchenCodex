import Foundation
import SwiftData

/// Builds the app's `ModelContainer`. The app, Share Extension and Widget extension all call this
/// so they open the same store in the shared App Group container.
public enum RecipeStore {
    /// TODO(Caleb): confirm the App Group ID and register it in the Developer portal.
    public static let appGroupIdentifier = "group.com.calebpietrafesa.RecipeCodex"
    public static let storeFileName = "RecipeCodex.store"

    public static var schema: Schema {
        Schema(versionedSchema: RecipeSchemaV1.self)
    }

    /// The store URL inside the App Group container, or `nil` when the group is unavailable
    /// (unregistered entitlement, or a test host).
    public static func sharedStoreURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appending(path: storeFileName)
    }

    /// Creates the container. CloudKit mirroring is off until the iCloud capability is enabled
    /// with Caleb's developer team (Phase 0 follow-up); flip `cloudKitDatabase` to `.automatic` then.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = schema
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if let url = sharedStoreURL() {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: RecipeMigrationPlan.self, configurations: [configuration])
    }
}
