import Foundation
import CoreData
import Observation

/// Watches SwiftData's CloudKit mirroring. SwiftData + CloudKit only reports
/// when an import starts and ends, so the restore UI is an indeterminate line.
@Observable
@MainActor
final class CloudSyncMonitor {
    enum State: Equatable { case idle, importing, failed }

    private(set) var state: State = .idle
    private(set) var lastSync: Date?
    /// True once the first import has finished on this install.
    private(set) var hasCompletedFirstImport: Bool
    private var observer: NSObjectProtocol?

    init() {
        hasCompletedFirstImport = UserDefaults.standard.bool(forKey: "lift.icloud.firstImportDone")
        lastSync = UserDefaults.standard.object(forKey: "lift.icloud.lastSync") as? Date
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let type = event.type
            let ended = event.endDate
            let ok = event.succeeded
            MainActor.assumeIsolated { self?.handle(type: type, endDate: ended, succeeded: ok) }
        }
    }

    /// Only a first restore on a new iPhone shows the loading state.
    var isRestoring: Bool { state == .importing && !hasCompletedFirstImport }
    var restoreFailed: Bool { state == .failed && !hasCompletedFirstImport }

    func retry() { state = .idle }

    #if DEBUG
    /// Screenshot fixtures only (frame 15).
    func debugSimulateFirstRestore() { hasCompletedFirstImport = false; state = .importing }
    #endif

    private func handle(type: NSPersistentCloudKitContainer.EventType, endDate: Date?, succeeded: Bool) {
        switch type {
        case .import:
            if endDate == nil {
                state = .importing
            } else if succeeded {
                state = .idle
                markSynced()
                if !hasCompletedFirstImport {
                    hasCompletedFirstImport = true
                    UserDefaults.standard.set(true, forKey: "lift.icloud.firstImportDone")
                }
            } else {
                state = .failed
            }
        case .export:
            if endDate != nil, succeeded { markSynced() }
        default:
            break
        }
    }

    private func markSynced() {
        lastSync = Date()
        UserDefaults.standard.set(lastSync, forKey: "lift.icloud.lastSync")
    }
}
