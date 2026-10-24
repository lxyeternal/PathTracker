import Foundation
import AuthenticationServices

/// Sign in with Apple. There is no server: the profile lives in iCloud key-value storage so
/// it follows the user to their other devices, and the data itself lives in their iCloud.
@MainActor
@Observable
final class AccountManager {
    struct Profile: Codable, Equatable {
        var userID: String
        var displayName: String?
        var email: String?
        var joinedAt: Date
    }

    private(set) var profile: Profile?
    private(set) var lastError: String?

    private let cloud = NSUbiquitousKeyValueStore.default
    private let profileKey = "account.profile"
    private var observer: NSObjectProtocol?

    init() {
        profile = loadProfile()
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.profile = self?.loadProfile() }
        }
        cloud.synchronize()
    }

    var isSignedIn: Bool { profile != nil }

    var greetingName: String {
        profile?.displayName?.components(separatedBy: " ").first ?? String(localized: "旅行者")
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            // Apple only sends the name and email the first time; keep what we already have.
            let name = credential.fullName.flatMap {
                PersonNameComponentsFormatter.localizedString(from: $0, style: .default).nilIfEmpty
            }
            var updated = profile?.userID == credential.user ? profile! :
                Profile(userID: credential.user, displayName: nil, email: nil, joinedAt: Date())
            updated.displayName = name ?? updated.displayName
            updated.email = credential.email ?? updated.email
            save(updated)
            lastError = nil
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                lastError = error.localizedDescription
            }
        }
    }

    func updateDisplayName(_ name: String) {
        guard var profile else { return }
        profile.displayName = name.trimmingCharacters(in: .whitespaces).nilIfEmpty
        save(profile)
    }

    /// If the user stopped using Apple ID with this app in Settings, sign them out here too.
    func verifyCredential() async {
        guard let userID = profile?.userID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        if state == .revoked || state == .notFound { signOut() }
    }

    func signOut() {
        profile = nil
        cloud.removeObject(forKey: profileKey)
        UserDefaults.standard.removeObject(forKey: profileKey)
        cloud.synchronize()
    }

    private func save(_ profile: Profile) {
        self.profile = profile
        if let data = try? JSONEncoder().encode(profile) {
            cloud.set(data, forKey: profileKey)
            UserDefaults.standard.set(data, forKey: profileKey)
            cloud.synchronize()
        }
    }

    private func loadProfile() -> Profile? {
        let data = cloud.data(forKey: profileKey) ?? UserDefaults.standard.data(forKey: profileKey)
        return data.flatMap { try? JSONDecoder().decode(Profile.self, from: $0) }
    }
}
