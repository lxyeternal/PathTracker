import Foundation
import CoreData
import Observation

/// What iCloud has done lately. SwiftData syncs on its own after every save and when other
/// devices change something; this listens to those events so Settings can say when the last
/// one finished, and "Sync Now" pushes anything not yet saved.
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    private(set) var lastSync: Date?
    private(set) var isSyncing = false
    private(set) var lastError: String?

    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        lastSync = UserDefaults.standard.object(forKey: "cloud.lastSync") as? Date
        observer = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                                          object: nil, queue: .main) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated { CloudSync.shared.handle(event) }
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        if event.type == .setup, let end = event.endDate {
            Diagnostics.record("cloud setup ok=\(event.succeeded) at=\(end) \(event.error.map { "\($0)" } ?? "")")
        }
        guard event.type == .import || event.type == .export else { return }
        if event.endDate == nil {
            isSyncing = true
            return
        }
        isSyncing = false
        Diagnostics.record("cloud \(event.type == .import ? "import" : "export") ok=\(event.succeeded) \(event.error.map { "\($0)" } ?? "")")
        if event.succeeded {
            lastSync = event.endDate
            lastError = nil
            UserDefaults.standard.set(event.endDate, forKey: "cloud.lastSync")
        } else {
            lastError = event.error?.localizedDescription
        }
    }

    /// Saves what's pending, which sends it to iCloud straight away. Changes from other devices
    /// arrive on their own; there is no way to ask iCloud for them sooner.
    func syncNow(_ save: () throws -> Void) {
        isSyncing = true
        do {
            try save()
        } catch {
            lastError = error.localizedDescription
        }
        Task {
            // If nothing was pending there is no event; don't leave the spinner running.
            try? await Task.sleep(for: .seconds(4))
            if isSyncing { isSyncing = false; lastSync = Date() }
        }
    }
}
