import CloudKit
import CoreData
import Foundation
import Observation
import OSLog
import RecipeModel

/// Whether the library syncs through iCloud, and if not, why (04 §5.1 "Sync state", ux-notes row
/// 56): which store the app opened (`RecipeCodexApp`), the iCloud account, and the CloudKit
/// mirroring events SwiftData's container posts (`NSPersistentCloudKitContainer.eventChangedNotification`).
/// Profile's About shows it, and Recipes flags a problem while it stands, so a device that will
/// never sync no longer looks like one that is slow to.
@MainActor
@Observable
final class SyncMonitor {
    /// The store `RecipeCodexApp` opened.
    enum Store: Equatable {
        /// The shared store, mirrored to the private CloudKit database.
        case cloudKit
        /// The CloudKit store couldn't be opened; the library is in a plain store on this device.
        case local(reason: String)
        /// Not even a local store opened; nothing is kept past this launch.
        case inMemory(reason: String)
    }

    /// What Profile and the Recipes flag say.
    enum State: Equatable {
        /// The CloudKit store is open and nothing has answered yet.
        case checking
        /// Syncing; the last import or export that finished, if any has.
        case on(lastChange: Date?)
        /// Syncing, but the network or iCloud is away for now; CloudKit retries on its own.
        case waiting(lastChange: Date?)
        case signedOut
        /// The account can't use iCloud (restricted, or temporarily unavailable).
        case accountUnavailable
        /// iCloud refused the app's container (a bad container, a missing entitlement, a
        /// permission failure).
        case containerUnavailable(String)
        case storageFull
        /// A sync failed for another reason; the next success clears it.
        case failing(String)
        case localStore(String)
        case inMemory(String)

        /// A problem the Recipes flag shows while it stands.
        var isIssue: Bool {
            switch self {
            case .checking, .on, .waiting: false
            default: true
            }
        }
    }

    let store: Store
    private(set) var accountStatus: CKAccountStatus?
    /// The last import or export that finished, kept across launches.
    private(set) var lastChange: Date?
    private var lastError: (code: CKError.Code?, message: String, isNoAccount: Bool)?
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    private static let lastChangeKey = "sync.lastChange"
    private static let logger = Logger(subsystem: "com.calebpietrafesa.RecipeCodex", category: "store")

    init(store: Store) {
        self.store = store
        lastChange = UserDefaults.standard.object(forKey: Self.lastChangeKey) as? Date
    }

    var state: State {
        switch store {
        case let .local(reason): return .localStore(reason)
        case let .inMemory(reason): return .inMemory(reason)
        case .cloudKit: break
        }
        switch accountStatus {
        case .noAccount?: return .signedOut
        case .restricted?, .temporarilyUnavailable?: return .accountUnavailable
        default: break
        }
        if let lastError {
            if lastError.isNoAccount { return .signedOut }
            switch lastError.code {
            case .notAuthenticated?: return .signedOut
            case .quotaExceeded?: return .storageFull
            case .networkUnavailable?, .networkFailure?, .serviceUnavailable?, .requestRateLimited?, .zoneBusy?:
                return .waiting(lastChange: lastChange)
            case .badContainer?, .missingEntitlement?, .permissionFailure?, .managedAccountRestricted?, .badDatabase?:
                return .containerUnavailable(lastError.message)
            default:
                return .failing(lastError.message)
            }
        }
        if accountStatus == nil, lastChange == nil { return .checking }
        return .on(lastChange: lastChange)
    }

    var hasIssue: Bool { state.isIssue }

    /// Starts listening: the mirroring events and account changes. Only a CloudKit store asks
    /// CloudKit anything, since a build without the container's entitlement can't.
    func start() {
        guard !isStarted, store == .cloudKit else { return }
        isStarted = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let summary = EventSummary(event)
            MainActor.assumeIsolated { self?.apply(summary) }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccount() }
        })
        refreshAccount()
    }

    private func refreshAccount() {
        Task {
            do {
                accountStatus = try await CKContainer(identifier: RecipeStore.cloudKitContainerIdentifier).accountStatus()
            } catch {
                Self.logger.error("iCloud account status unavailable: \(error.localizedDescription, privacy: .public)")
                accountStatus = .couldNotDetermine
            }
        }
    }

    /// What a finished mirroring event says: a success records the change (an import or an
    /// export) and clears the last error; a failure records why.
    private func apply(_ event: EventSummary) {
        guard let end = event.endDate else { return }
        if event.succeeded {
            lastError = nil
            if event.isTransfer {
                lastChange = end
                UserDefaults.standard.set(end, forKey: Self.lastChangeKey)
            }
        } else if let message = event.errorMessage {
            lastError = (event.errorCode, message, event.isNoAccount)
            Self.logger.error("CloudKit \(event.kind, privacy: .public) failed: \(message, privacy: .public)")
        }
    }

    /// The parts of a mirroring event the monitor keeps, read where the notification arrives.
    nonisolated private struct EventSummary: Sendable {
        let kind: String
        let isTransfer: Bool
        let endDate: Date?
        let succeeded: Bool
        let errorCode: CKError.Code?
        let errorMessage: String?
        /// Core Data's "Unable to initialize without an iCloud account" (134400).
        let isNoAccount: Bool

        init(_ event: NSPersistentCloudKitContainer.Event) {
            switch event.type {
            case .setup: kind = "setup"
            case .import: kind = "import"
            case .export: kind = "export"
            @unknown default: kind = "event"
            }
            isTransfer = event.type == .import || event.type == .export
            endDate = event.endDate
            succeeded = event.succeeded
            let error = event.error.map { $0 as NSError }
            isNoAccount = error?.domain == NSCocoaErrorDomain && error?.code == 134400
            // A partial failure wraps the errors that matter; the first says why.
            if let error, error.domain == CKError.errorDomain,
               let partial = (error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError])?.values.first {
                errorCode = CKError.Code(rawValue: partial.code)
                errorMessage = partial.localizedDescription
            } else if let error {
                errorCode = error.domain == CKError.errorDomain ? CKError.Code(rawValue: error.code) : nil
                errorMessage = error.localizedDescription
            } else {
                errorCode = nil
                errorMessage = nil
            }
        }
    }
}

extension SyncMonitor.State {
    /// Profile's row: "iCloud sync on · last change 2 minutes ago", or the problem in a few words.
    func summary(now: Date = .now) -> String {
        switch self {
        case .checking: "iCloud sync on · checking"
        case let .on(lastChange):
            lastChange.map { "iCloud sync on · last change \(Self.relative($0, now: now))" } ?? "iCloud sync on · nothing synced yet"
        case .waiting: "iCloud sync on · waiting for the network"
        case .signedOut: "Not syncing · signed out of iCloud"
        case .accountUnavailable: "Not syncing · iCloud unavailable on this device"
        case .containerUnavailable: "Not syncing · the iCloud container is unavailable"
        case .storageFull: "Not syncing · iCloud storage is full"
        case .failing: "Not syncing · the last sync failed"
        case .localStore: "Not syncing · using a local store on this device"
        case .inMemory: "Not saving · the library is in memory only"
        }
    }

    /// The Recipes flag's line.
    var flagTitle: String {
        switch self {
        case .signedOut: "Signed out of iCloud: your library isn't syncing"
        case .storageFull: "iCloud storage is full: your library isn't syncing"
        case .inMemory: "Your library isn't being saved"
        default: "Your library isn't syncing with iCloud"
        }
    }

    /// The detail: what is happening and what to do.
    var explanation: String {
        switch self {
        case .checking:
            "Kitchen Codex is checking with iCloud."
        case .on:
            "Your library syncs through iCloud with your other devices signed in to the same Apple Account."
        case .waiting:
            "iCloud can't be reached right now. Changes are kept on this device and sync once it can be reached again."
        case .signedOut:
            "This device isn't signed in to iCloud, so recipes you add here stay here. Sign in to iCloud in Settings to sync your library."
        case .accountUnavailable:
            "iCloud isn't available to Kitchen Codex on this device just now (it may be restricted, or still starting). Changes stay on this device until it is."
        case .containerUnavailable:
            "iCloud turned down Kitchen Codex's container, so nothing syncs. Changes stay on this device."
        case .storageFull:
            "Your iCloud storage is full, so changes stay on this device until there's room."
        case .failing:
            "The last sync with iCloud failed. Kitchen Codex tries again on its own; changes stay on this device until one succeeds."
        case .localStore:
            "Kitchen Codex couldn't open its iCloud store, so it's keeping your library in a store on this device only. Recipes added here don't reach your other devices, and theirs don't arrive here."
        case .inMemory:
            "Kitchen Codex couldn't open a store at all, so the library lives in memory and is lost when the app quits."
        }
    }

    /// The error behind the problem, for the detail's footnote.
    var reason: String? {
        switch self {
        case let .containerUnavailable(reason), let .failing(reason), let .localStore(reason), let .inMemory(reason): reason
        default: nil
        }
    }

    var systemImage: String {
        switch self {
        case .on, .checking: "checkmark.icloud"
        case .waiting: "icloud.slash"
        default: "exclamationmark.icloud"
        }
    }

    /// "2 minutes ago".
    static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
    }
}
