import Foundation
import SwiftData
import CloudKit

enum PersistenceController {
    static let schema = Schema([TrackChunk.self, Stay.self, Trip.self, TripPhoto.self])

    /// iCloud sync turns on by itself once the app is signed and the device has an iCloud
    /// account; otherwise the same store simply stays on device.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let cloudAvailable = !inMemory && FileManager.default.ubiquityIdentityToken != nil
        // Each in-memory container gets its own name so tests never see each other's data.
        let name = inMemory ? "Memory-\(UUID().uuidString)" : "PathTracker"
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudAvailable ? .automatic : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // A local-only store is better than not launching at all.
            let fallback = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: inMemory,
                                              cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: fallback)
            } catch {
                fatalError("Could not create the data store: \(error)")
            }
        }
    }
}

enum SyncStatus: Equatable {
    case checking, available, noAccount, restricted, unavailable

    var title: String {
        switch self {
        case .checking: String(localized: "正在检查…")
        case .available: String(localized: "已开启")
        case .noAccount: String(localized: "未登录 iCloud")
        case .restricted: String(localized: "受限制")
        case .unavailable: String(localized: "暂不可用")
        }
    }

    static func current() async -> SyncStatus {
        guard FileManager.default.ubiquityIdentityToken != nil else { return .noAccount }
        do {
            switch try await CKContainer.default().accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            default: return .unavailable
            }
        } catch {
            return .unavailable
        }
    }
}
