import OSLog
import RecipeModel
import SwiftData
import SwiftUI

@main
struct RecipeCodexApp: App {
    private let container: ModelContainer

    init() {
        let logger = Logger(subsystem: "com.calebpietrafesa.RecipeCodex", category: "store")
        do {
            container = try RecipeStore.makeContainer(syncsWithCloudKit: true)
        } catch {
            // Without the iCloud entitlement or container (a build without the team, or a test
            // host) keep the data local rather than losing it; only if even that fails go in-memory.
            logger.error("CloudKit store unavailable, using a local store: \(error.localizedDescription)")
            do {
                container = try RecipeStore.makeContainer()
            } catch {
                logger.error("Falling back to an in-memory store: \(error.localizedDescription)")
                do {
                    container = try RecipeStore.makeContainer(inMemory: true)
                } catch {
                    fatalError("Could not create even an in-memory store: \(error)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
