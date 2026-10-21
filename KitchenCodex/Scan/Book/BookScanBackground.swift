import BackgroundTasks
import Foundation
import OSLog
import SwiftData

/// The whole-book session's backlog read while the app is away (ux-notes row 92, 04 §5.1 "Whole-book
/// session"): a `BGProcessingTask` registered at launch, asked for when the scene goes to the
/// background with captures still waiting, that resumes every such book through `BookScanStore`
/// and drains it. When the system calls time, the workers stop between captures; what wasn't read
/// stays pending for the next chance (the next task, or the app's next launch), and another task is
/// asked for. The project carries the "processing" background mode and the identifier.
///
/// The launch handler is registered on the main queue, so it runs on the main actor as the store
/// and sessions need. The expiration handler is `@Sendable`: the system may call it on another
/// queue, and a main-actor closure there would trap at its executor check (slice 4's camera crash).
enum BookScanBackground {
    static let identifier = "com.calebpietrafesa.KitchenCodex.bookscan"

    private static let logger = Logger(subsystem: "com.calebpietrafesa.KitchenCodex", category: "scan")

    /// What the handler decides, apart from BackgroundTasks so it can be checked on its own.
    enum Decision {
        /// A request is worth submitting only with captures waiting.
        static func shouldSubmit(pendingBooks: [UUID]) -> Bool { !pendingBooks.isEmpty }

        /// After a run, from whether time ran out and what is still waiting: a success only when the
        /// run finished with nothing left, and another request whenever something is.
        static func outcome(expired: Bool, pendingAfter: [UUID]) -> (success: Bool, resubmits: Bool) {
            (!expired && pendingAfter.isEmpty, !pendingAfter.isEmpty)
        }
    }

    /// Registers the task; called from `KitchenCodexApp.init`, before launch finishes.
    @MainActor
    static func register(container: ModelContainer) {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                let run = Run(complete: { task.setTaskCompleted(success: $0) }, container: container)
                task.expirationHandler = { @Sendable in
                    Task { @MainActor in run.expire() }
                }
                run.start()
            }
        }
        if !registered { logger.error("Book scans: the background task couldn't be registered") }
    }

    /// The scene went to the background: a request for the task, when captures are waiting. No
    /// network is needed and external power isn't required.
    @MainActor
    static func submitIfNeeded() {
        let pending = BookScanState.booksWithPendingCaptures()
        guard Decision.shouldSubmit(pendingBooks: pending) else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Book scans: asked for background time for \(pending.count) books")
        } catch {
            // The Simulator can't run background tasks: the queue catches up when the app opens.
            logger.error("Book scans: no background task (\(error.localizedDescription, privacy: .public))")
        }
    }

    /// One run of the task: drain, then complete once, whichever comes first of the end of the
    /// drain and the system's expiration.
    @MainActor
    final class Run {
        private let complete: (Bool) -> Void
        private let container: ModelContainer
        private var isFinished = false
        private var work: Task<Void, Never>?

        init(complete: @escaping (Bool) -> Void, container: ModelContainer) {
            self.complete = complete
            self.container = container
        }

        func start() {
            let context = container.mainContext
            work = Task { @MainActor in
                await BookScanStore.shared.drainAll(in: context)
                self.finish(expired: false)
            }
        }

        /// Time's up: the workers stop after the capture in hand, the rest wait.
        func expire() {
            BookScanStore.shared.stopWorkers()
            work?.cancel()
            finish(expired: true)
        }

        private func finish(expired: Bool) {
            guard !isFinished else { return }
            isFinished = true
            let pending = BookScanState.booksWithPendingCaptures()
            let outcome = Decision.outcome(expired: expired, pendingAfter: pending)
            BookScanBackground.logger.info("Book scans: background run \(expired ? "expired" : "finished"), \(pending.count) books still waiting")
            if outcome.resubmits { BookScanBackground.submitIfNeeded() }
            complete(outcome.success)
        }
    }

    #if DEBUG
    /// The handler's path without the system's task, for the Simulator, which can't launch one:
    /// launched with `-KitchenCodexDrainBookScans`, the app drains as the task would and logs the
    /// outcome; with `-KitchenCodexExpireBookScans` too, time runs out two seconds in.
    @MainActor
    static func runWithoutSystemTask(container: ModelContainer, expiresAfter seconds: Double? = nil) {
        let run = Run(complete: { success in logger.info("Book scans: debug run completed, success \(success)") }, container: container)
        run.start()
        if let seconds {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                run.expire()
            }
        }
    }
    #endif
}
