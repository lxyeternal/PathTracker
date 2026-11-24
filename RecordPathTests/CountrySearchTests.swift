import Foundation
import Testing
@testable import RecordPath

/// Finding a country in the list by typing: in Chinese, in English, by pinyin or by code.
struct CountrySearchTests {
    private let choices = ["JP", "CN", "US", "CI", "KR", "NE", "NG"].map {
        CountryChoice(code: $0, name: Locale(identifier: "zh-Hans").localizedString(forRegionCode: $0) ?? $0)
    }

    private func codes(_ text: String) -> [String] { CountryChoice.search(choices, for: text).map(\.code) }

    @Test func aCountryIsFoundByItsNameInEitherLanguage() {
        #expect(codes("日本") == ["JP"])
        #expect(codes("japan") == ["JP"])
        #expect(codes("Cote") == ["CI"])
        #expect(codes(" 美国 ") == ["US"])
    }

    @Test func pinyinItsInitialsAndTheCodeFindItToo() {
        #expect(codes("riben") == ["JP"])
        #expect(codes("rb") == ["JP"])
        #expect(codes("kr") == ["KR"])
        #expect(codes("meiguo") == ["US"])
    }

    @Test func namesThatStartWithTheTextComeFirstAndNothingTypedShowsAll() {
        #expect(codes("ni").prefix(2).sorted() == ["NE", "NG"])
        #expect(codes("国") == ["CN", "KR", "US"] || Set(codes("国")) == ["CN", "KR", "US"])
        #expect(codes("").count == choices.count)
        #expect(codes("zzzz").isEmpty)
    }
}
