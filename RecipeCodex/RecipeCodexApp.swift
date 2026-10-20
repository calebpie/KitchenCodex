import OSLog
import RecipeModel
import SwiftData
import SwiftUI

@main
struct RecipeCodexApp: App {
    private let container: ModelContainer
    private let spotlight: RecipeSpotlightIndexer
    @Environment(\.scenePhase) private var scenePhase

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
        spotlight = RecipeSpotlightIndexer(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    // Before indexing, so Spotlight sees the re-read items.
                    IngredientReread.runOnce(in: container.mainContext)
                    spotlight.start()
                }
        }
        .modelContainer(container)
        // The iPad menu bar and hardware-keyboard shortcuts (03 §4).
        .commands { RecipeCodexCommands() }
        .onChange(of: scenePhase) { _, phase in
            // Recipes saved by the Share Extension, or synced from another device, arrive while the
            // app is away; index them when it comes back.
            if phase == .active { spotlight.scheduleSync() }
        }
    }
}
