import Foundation
import AuthenticationServices
import UIKit

/// The user's profile (name, email, a short bio and an avatar) plus an optional Sign in with
/// Apple link. There is no server: everything lives in iCloud key-value storage so it follows
/// the user to their other devices.
@MainActor
@Observable
final class AccountManager {
    struct Profile: Codable, Equatable {
        /// Set once the user has signed in with Apple.
        var userID: String?
        var displayName: String?
        var email: String?
        var bio: String?
        var joinedAt: Date = Date()
    }

    private(set) var profile = Profile()
    private(set) var avatar: UIImage?
    private(set) var lastError: String?

    private let cloud = NSUbiquitousKeyValueStore.default
    private let profileKey = "account.profile"
    private let avatarKey = "account.avatar"
    private var observer: NSObjectProtocol?

    /// Avatars are stored small: key-value storage allows 1 MB in total.
    static let avatarSide: CGFloat = 400

    init() {
        load()
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
        cloud.synchronize()
    }

    var isSignedIn: Bool { profile.userID != nil }

    var displayName: String { profile.displayName ?? String(localized: "旅行者", bundle: .appLanguage) }

    var greetingName: String {
        profile.displayName?.components(separatedBy: " ").first ?? String(localized: "旅行者", bundle: .appLanguage)
    }

    // MARK: Editing

    func update(name: String, email: String, bio: String) {
        profile.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        profile.email = email.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        profile.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        saveProfile()
    }

    /// Crops to a centred square and scales down before storing.
    func setAvatar(from data: Data) {
        guard let image = UIImage(data: data), let square = Self.squareAvatar(from: image) else { return }
        avatar = square
        if let jpeg = square.jpegData(compressionQuality: 0.8) {
            cloud.set(jpeg, forKey: avatarKey)
            UserDefaults.standard.set(jpeg, forKey: avatarKey)
            cloud.synchronize()
        }
    }

    func removeAvatar() {
        avatar = nil
        cloud.removeObject(forKey: avatarKey)
        UserDefaults.standard.removeObject(forKey: avatarKey)
        cloud.synchronize()
    }

    static func squareAvatar(from image: UIImage) -> UIImage? {
        let size = image.size
        let side = min(size.width, size.height)
        guard side > 0 else { return nil }
        let target = min(side, avatarSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let scale = target / side
            let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
            image.draw(in: CGRect(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
    }

    // MARK: Sign in with Apple

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            // Apple only sends the name and email the first time; never overwrite what the user typed.
            let name = credential.fullName.flatMap {
                PersonNameComponentsFormatter.localizedString(from: $0, style: .default).nilIfEmpty
            }
            profile.userID = credential.user
            profile.displayName = profile.displayName ?? name
            profile.email = profile.email ?? credential.email
            saveProfile()
            lastError = nil
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                lastError = error.localizedDescription
            }
        }
    }

    /// If the user stopped using Apple ID with this app in Settings, unlink it here too.
    func verifyCredential() async {
        guard let userID = profile.userID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        if state == .revoked || state == .notFound { signOut() }
    }

    /// Unlinks Apple ID; the name and avatar stay, they belong to the user, not the login.
    func signOut() {
        profile.userID = nil
        saveProfile()
    }

    /// Removes everything, for "delete all data".
    func reset() {
        profile = Profile()
        removeAvatar()
        cloud.removeObject(forKey: profileKey)
        UserDefaults.standard.removeObject(forKey: profileKey)
        cloud.synchronize()
    }

    // MARK: Storage

    private func saveProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        cloud.set(data, forKey: profileKey)
        UserDefaults.standard.set(data, forKey: profileKey)
        cloud.synchronize()
    }

    private func load() {
        let data = cloud.data(forKey: profileKey) ?? UserDefaults.standard.data(forKey: profileKey)
        profile = data.flatMap { try? JSONDecoder().decode(Profile.self, from: $0) } ?? Profile()
        let image = cloud.data(forKey: avatarKey) ?? UserDefaults.standard.data(forKey: avatarKey)
        avatar = image.flatMap(UIImage.init(data:))
    }
}
