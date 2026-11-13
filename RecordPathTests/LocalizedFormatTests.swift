import Testing
import Foundation
@testable import RecordPath

/// Every string with numbers in it is built once in each language. A format that doesn't match
/// its arguments crashes on the phone of whoever happens to see it, not in a build.
struct LocalizedFormatTests {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test(arguments: ["en", "zh-Hans"])
    func dayCountsReadInBothLanguages(language: String) throws {
        let b = try bundle(language)
        for n in [0, 1, 2, 73] {
            let name = "Japan"
            let texts = [
                String(localized: "\(n) 天 · \(n) 座城市 · 最近 \(name)", bundle: b),
                String(localized: "\(n) 次 · \(n) 天", bundle: b),
                String(localized: "\(n) 次入境 · 共 \(n) 天", bundle: b),
                String(localized: "\(name) 还剩 \(n) 天到期", bundle: b),
                String(localized: "\(name)签证还有 \(n) 天到期", bundle: b),
                String(localized: "\(name) \(n) 天后到期", bundle: b),
                String(localized: "离\(name)还有 \(n) 天。去哪儿，现在想正好。", bundle: b),
                String(localized: "最近 180 天里，你在申根区待了 \(n) 天，还能再待 \(n) 天。", bundle: b),
                String(localized: "\(n) 天前", bundle: b),
                String(localized: "还剩 \(n) 天", bundle: b),
                String(localized: "\(n) 天后，你到了这里", bundle: b),
                String(localized: "还在等你 · 收下 \(n) 天了", bundle: b),
                String(localized: "\(n) 天前，盲盒把这里交给了你。\n你真的来了。", bundle: b),
                String(localized: "还有 \(n) 天到周末。先给自己留个念想。", bundle: b),
                String(localized: "每次停留 \(n) 天", bundle: b),
                String(localized: "护照还有 \(n) 天到期", bundle: b),
                String(localized: "有 \(n) 张登机牌在等你", bundle: b),
                String(localized: "今天还能拆 \(n) 次", bundle: b),
                String(localized: "从 \(name) 至今", bundle: b),
            ]
            for text in texts {
                #expect(text.contains("\(n)") || text.contains(name), Comment(rawValue: text))
                #expect(!text.contains("%"), Comment(rawValue: text))
            }
        }
    }
}
