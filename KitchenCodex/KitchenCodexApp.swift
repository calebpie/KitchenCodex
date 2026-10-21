import OSLog
import RecipeModel
import SwiftData
import SwiftUI

@main
struct KitchenCodexApp: App {
    private let container: ModelContainer
    private let spotlight: RecipeSpotlightIndexer
    /// Which store opened, and whether it syncs: Profile says, and Recipes flags a problem (04 §5.1
    /// "Sync state").
    @State private var sync: SyncMonitor
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let logger = Logger(subsystem: "com.calebpietrafesa.KitchenCodex", category: "store")
        let store: SyncMonitor.Store
        do {
            #if DEBUG
            // Shows the local-store state on purpose (Profile's sync row, the Recipes flag).
            if ProcessInfo.processInfo.arguments.contains("-KitchenCodexLocalStore") {
                throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey: "Launched with -KitchenCodexLocalStore."])
            }
            #endif
            container = try RecipeStore.makeContainer(syncsWithCloudKit: true)
            store = .cloudKit
        } catch {
            // Without the iCloud entitlement or container (a build without the team, or a test
            // host) keep the data local rather than losing it; only if even that fails go in-memory.
            // Either way the app says so (SyncMonitor), never silently.
            logger.error("CloudKit store unavailable, using a local store: \(error.localizedDescription)")
            let cloudKitError = error.localizedDescription
            do {
                container = try RecipeStore.makeContainer()
                store = .local(reason: cloudKitError)
            } catch {
                logger.error("Falling back to an in-memory store: \(error.localizedDescription)")
                do {
                    container = try RecipeStore.makeContainer(inMemory: true)
                    store = .inMemory(reason: error.localizedDescription)
                } catch {
                    fatalError("Could not create even an in-memory store: \(error)")
                }
            }
        }
        spotlight = RecipeSpotlightIndexer(container: container)
        _sync = State(initialValue: SyncMonitor(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(sync)
                .task {
                    sync.start()
                    // Before indexing, so Spotlight sees the re-read items.
                    IngredientReread.runOnce(in: container.mainContext)
                    spotlight.start()
                    // A whole-book session's captures left waiting at the last quit are read now.
                    BookScanStore.shared.resume(in: container.mainContext)
                }
        }
        .modelContainer(container)
        // The iPad menu bar and hardware-keyboard shortcuts (03 §4).
        .commands { KitchenCodexCommands() }
        .onChange(of: scenePhase) { _, phase in
            // Recipes saved by the Share Extension, or synced from another device, arrive while the
            // app is away; index them when it comes back.
            if phase == .active { spotlight.scheduleSync() }
        }
    }
}
