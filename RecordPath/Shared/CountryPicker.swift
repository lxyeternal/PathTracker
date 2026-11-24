import SwiftUI

/// One row of a country list: a country, or something listed with them ("申根区").
struct CountryChoice: Identifiable, Hashable {
    let code: String
    let flag: String
    let name: String
    /// Its names, lowercased: in the app's language, in Chinese and in English. A search may
    /// match anywhere in them.
    let names: [String]
    /// The code and, for Chinese names, the pinyin and its initials. These only match from
    /// their start: "rb" is 日本, not every name with those two letters somewhere in its pinyin.
    let shorthands: [String]

    var id: String { code }

    init(code: String, flag: String? = nil, name: String, alsoFoundBy extra: [String] = []) {
        self.code = code
        self.flag = flag ?? .flag(for: code)
        self.name = name
        var words = [name] + extra
        for locale in ["zh-Hans", "en"] {
            if let other = Locale(identifier: locale).localizedString(forRegionCode: code) { words.append(other) }
        }
        var shorthands = [Self.folded(code)]
        for word in words where CityNames.hasHan(word) {
            let syllables = (word.applyingTransform(.toLatin, reverse: false) ?? "")
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .split(separator: " ")
            shorthands.append(syllables.joined())
            shorthands.append(String(syllables.compactMap(\.first)))
        }
        self.names = words.map(Self.folded).filter { !$0.isEmpty }
        self.shorthands = shorthands.filter { !$0.isEmpty }
    }

    /// Lowercased, without accents or spaces: "Côte d’Ivoire" is found by "cote".
    static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: " ", with: "")
    }

    /// Names that start with what was typed come before names that only contain it.
    static func search(_ choices: [CountryChoice], for text: String) -> [CountryChoice] {
        let query = folded(text.trimmingCharacters(in: .whitespaces))
        guard !query.isEmpty else { return choices }
        let starting = choices.filter { choice in (choice.names + choice.shorthands).contains { $0.hasPrefix(query) } }
        let containing = choices.filter { choice in
            !starting.contains(choice) && choice.names.contains { $0.contains(query) }
        }
        return starting + containing
    }

    static var all: [CountryChoice] { Nationality.all.map { CountryChoice(code: $0.code, name: $0.name) } }
}

/// A form row that opens every country as a list to search, instead of one to scroll through.
/// `leading` are the choices listed before the countries.
struct CountryPickerRow: View {
    let title: LocalizedStringKey
    @Binding var selection: String
    var leading: [CountryChoice] = []

    @State private var choices: [CountryChoice] = []

    private var current: CountryChoice? {
        leading.first { $0.code == selection } ?? choices.first { $0.code == selection }
    }

    var body: some View {
        NavigationLink {
            CountryList(title: title, selection: $selection, leading: leading, countries: choices)
        } label: {
            LabeledContent(title) {
                if let current {
                    Text(verbatim: [current.flag, current.name].filter { !$0.isEmpty }.joined(separator: " "))
                } else if !selection.isEmpty {
                    Text(verbatim: "\(String.flag(for: selection)) \(appLocale.localizedString(forRegionCode: selection) ?? selection)")
                }
            }
        }
        // Pinyin for some 250 names takes a moment; done once, off the row's first draw.
        .task { if choices.isEmpty { choices = CountryChoice.all } }
    }
}

private struct CountryList: View {
    let title: LocalizedStringKey
    @Binding var selection: String
    let leading: [CountryChoice]
    let countries: [CountryChoice]
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var found: [CountryChoice] { CountryChoice.search(leading + countries, for: query) }

    var body: some View {
        List {
            if searching {
                ForEach(found) { row($0) }
            } else {
                if !leading.isEmpty { Section { ForEach(leading) { row($0) } } }
                Section { ForEach(countries) { row($0) } }
            }
        }
        .overlay {
            if searching, found.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索国家或地区")
        .autocorrectionDisabled()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ choice: CountryChoice) -> some View {
        Button {
            selection = choice.code
            dismiss()
        } label: {
            HStack(spacing: 10) {
                if !choice.flag.isEmpty { Text(verbatim: choice.flag) }
                Text(verbatim: choice.name).foregroundStyle(Color.primary)
                Spacer()
                if choice.code == selection {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(choice.code == selection ? .isSelected : [])
    }
}
