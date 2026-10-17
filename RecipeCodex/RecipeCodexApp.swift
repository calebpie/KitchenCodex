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
            container = try RecipeStore.makeContainer()
        } catch {
            // Phase 0: keep the app usable if the shared store cannot open (for example an
            // unregistered App Group on a device). Data entered in this state is not kept.
            logger.error("Falling back to an in-memory store: \(error.localizedDescription)")
            do {
                container = try RecipeStore.makeContainer(inMemory: true)
            } catch {
                fatalError("Could not create even an in-memory store: \(error)")
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
