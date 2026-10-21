import Foundation
import SwiftData

/// Builds the app's `ModelContainer`. The app, Share Extension and Widget extension all call this
/// so they open the same store in the shared App Group container.
public enum RecipeStore {
    public static let appGroupIdentifier = "group.com.calebpietrafesa.KitchenCodex"
    public static let cloudKitContainerIdentifier = "iCloud.com.calebpietrafesa.KitchenCodex"
    public static let storeFileName = "KitchenCodex.store"

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

    /// Creates the container.
    ///
    /// - `syncsWithCloudKit`: mirror the store to the private CloudKit database. Only the app
    ///   target passes `true`; it carries the iCloud entitlement and does the syncing. The Share and
    ///   Widget extensions open the same store file without mirroring; SwiftData records their
    ///   changes in persistent history and the app exports them on its next launch.
    public static func makeContainer(inMemory: Bool = false, syncsWithCloudKit: Bool = false) throws -> ModelContainer {
        let schema = schema
        let database: ModelConfiguration.CloudKitDatabase = syncsWithCloudKit ? .private(cloudKitContainerIdentifier) : .none
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if let url = sharedStoreURL() {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: database)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: database)
        }
        return try ModelContainer(for: schema, migrationPlan: RecipeMigrationPlan.self, configurations: [configuration])
    }
}
