import SwiftUI
import Observation

/// The look of the passport: the cover's leather and foil, and the paper, print and security
/// pattern of the pages inside. In the spirit of real passports, copying none of them.
enum PassportTheme: String, CaseIterable, Identifiable {
    case burgundy, navy, forest, midnight

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .burgundy: "酒红"
        case .navy: "藏青"
        case .forest: "墨绿"
        case .midnight: "夜黑"
        }
    }

    var leather: Color {
        switch self {
        case .burgundy: Color(red: 0.37, green: 0.08, blue: 0.13)
        case .navy: Color(red: 0.07, green: 0.13, blue: 0.29)
        case .forest: Color(red: 0.09, green: 0.24, blue: 0.18)
        case .midnight: Color(red: 0.09, green: 0.09, blue: 0.10)
        }
    }

    var foil: LinearGradient {
        let colors: [Color] = switch self {
        case .navy:
            // Silver.
            [Color(red: 0.93, green: 0.94, blue: 0.96), Color(red: 0.64, green: 0.68, blue: 0.75), Color(red: 0.97, green: 0.98, blue: 1)]
        case .midnight:
            // Pale champagne gold, finer against black.
            [Color(red: 0.95, green: 0.88, blue: 0.70), Color(red: 0.74, green: 0.64, blue: 0.45), Color(red: 0.97, green: 0.91, blue: 0.74)]
        default:
            [Color(red: 0.93, green: 0.80, blue: 0.50), Color(red: 0.75, green: 0.58, blue: 0.30), Color(red: 0.95, green: 0.84, blue: 0.56)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The emblem in the middle of the cover.
    var emblem: String {
        switch self {
        case .burgundy: "globe.asia.australia.fill"
        case .navy: "safari.fill"
        case .forest: "mountain.2.fill"
        case .midnight: "moon.stars.fill"
        }
    }

    var paper: Color {
        switch self {
        case .burgundy: StampPaper.color
        case .navy: Color(red: 0.94, green: 0.955, blue: 0.97)
        case .forest: Color(red: 0.95, green: 0.955, blue: 0.915)
        case .midnight: Color(red: 0.955, green: 0.948, blue: 0.935)
        }
    }

    /// The fine security lines printed on the pages.
    var guilloche: Color {
        switch self {
        case .burgundy: StampPaper.line
        case .navy: Color(red: 0.72, green: 0.79, blue: 0.89)
        case .forest: Color(red: 0.74, green: 0.83, blue: 0.72)
        case .midnight: Color(red: 0.80, green: 0.77, blue: 0.74)
        }
    }

    /// The ink of the printed text.
    var printed: Color {
        switch self {
        case .burgundy: Color(red: 0.25, green: 0.22, blue: 0.30)
        case .navy: Color(red: 0.14, green: 0.20, blue: 0.34)
        case .forest: Color(red: 0.16, green: 0.26, blue: 0.21)
        case .midnight: Color(red: 0.18, green: 0.18, blue: 0.20)
        }
    }

    var pattern: StampPaper.Pattern {
        switch self {
        case .burgundy: .waves
        case .navy: .lattice
        case .forest: .ripples
        case .midnight: .rosette
        }
    }
}

/// The chosen theme, kept in iCloud so every device shows the same passport.
@MainActor
@Observable
final class PassportStyle {
    static let shared = PassportStyle()
    private static let key = "passport.theme"
    private static let chosenKey = "passport.themeChosen"

    /// Set once the person has picked a cover; until then the passport offers the four.
    var hasChosen: Bool {
        didSet {
            UserDefaults.standard.set(hasChosen, forKey: Self.chosenKey)
            NSUbiquitousKeyValueStore.default.set(hasChosen, forKey: Self.chosenKey)
        }
    }

    var theme: PassportTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
            NSUbiquitousKeyValueStore.default.set(theme.rawValue, forKey: Self.key)
        }
    }

    private init() {
        let stored = NSUbiquitousKeyValueStore.default.string(forKey: Self.key) ?? UserDefaults.standard.string(forKey: Self.key)
        theme = stored.flatMap(PassportTheme.init(rawValue:)) ?? .burgundy
        hasChosen = NSUbiquitousKeyValueStore.default.bool(forKey: Self.chosenKey) || UserDefaults.standard.bool(forKey: Self.chosenKey)
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: NSUbiquitousKeyValueStore.default, queue: .main) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard keys.contains(Self.key) || keys.contains(Self.chosenKey) else { return }
            MainActor.assumeIsolated {
                if NSUbiquitousKeyValueStore.default.bool(forKey: Self.chosenKey), !PassportStyle.shared.hasChosen {
                    PassportStyle.shared.hasChosen = true
                }
                if let raw = NSUbiquitousKeyValueStore.default.string(forKey: Self.key), let theme = PassportTheme(rawValue: raw),
                   theme != PassportStyle.shared.theme {
                    PassportStyle.shared.theme = theme
                }
            }
        }
    }
}

/// The four covers side by side, the chosen one lifted.
struct PassportThemePicker: View {
    @Binding var selection: PassportTheme

    var body: some View {
        HStack(spacing: 18) {
            ForEach(PassportTheme.allCases) { theme in
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { selection = theme }
                } label: {
                    VStack(spacing: 8) {
                        PassportCover(compact: true, theme: theme)
                            .frame(width: 44, height: 62)
                            .shadow(color: .black.opacity(selection == theme ? 0.28 : 0.12), radius: selection == theme ? 8 : 3,
                                    y: selection == theme ? 5 : 2)
                            .scaleEffect(selection == theme ? 1.08 : 1)
                            .offset(y: selection == theme ? -4 : 0)
                        Text(theme.title)
                            .font(.caption.weight(selection == theme ? .semibold : .regular))
                            .foregroundStyle(selection == theme ? .primary : .secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The first time the passport is opened: the four covers to try, and a button to settle on
/// one. Once chosen it steps aside; Settings has it after that.
struct PassportFirstChoice: View {
    @Bindable var style: PassportStyle

    var body: some View {
        VStack(spacing: 14) {
            Text("选一本你喜欢的护照").font(.subheadline.weight(.semibold))
            PassportThemePicker(selection: $style.theme)
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { style.hasChosen = true }
            } label: {
                Text("就选这本").font(.subheadline.weight(.semibold)).padding(.horizontal, 10)
            }
            .buttonStyle(.glassProminent)
            Text("以后可以在设置里更换").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        .sensoryFeedback(.success, trigger: style.hasChosen)
    }
}
