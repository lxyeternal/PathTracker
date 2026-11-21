import Foundation
import Testing
@testable import RecordPath

/// The invitation link: our own page, told which iCloud holds the share.
struct ParallelInviteTests {
    private let page = URL(string: "https://waytrace.cn/join.html")!

    private func items(_ url: URL?) -> [String: String] {
        let found = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0.value ?? "") })
    }

    @Test func aShareOutsideChinaGoesToICloudCom() {
        let link = URL(string: "https://www.icloud.com/share/0a1B2c3D4e5F6g7H8#Waytrace")!
        let url = ParallelSharing.inviteURL(page: page, shareLink: link, from: "小蓝")
        #expect(url?.host() == "waytrace.cn")
        #expect(items(url) == ["s": "0a1B2c3D4e5F6g7H8", "n": "小蓝"])
    }

    @Test func aShareInMainlandChinaSaysSo() {
        let link = URL(string: "https://www.icloud.com.cn/share/0a1B2c3D4e5F6g7H8#Waytrace")!
        let url = ParallelSharing.inviteURL(page: page, shareLink: link, from: nil)
        #expect(items(url) == ["s": "0a1B2c3D4e5F6g7H8", "h": "cn"])
    }

    @Test func aBlankNameIsLeftOutAndALongOneCut() {
        let link = URL(string: "https://www.icloud.com/share/0a1B2c3D4e5F6g7H8")!
        #expect(items(ParallelSharing.inviteURL(page: page, shareLink: link, from: "  "))["n"] == nil)
        let long = String(repeating: "长", count: 50)
        #expect(items(ParallelSharing.inviteURL(page: page, shareLink: link, from: long))["n"]?.count == 30)
    }

    @Test func aLinkFromAnywhereElseIsNotWrapped() {
        #expect(ParallelSharing.inviteURL(page: page, shareLink: URL(string: "https://example.com/share/abcdefgh")!, from: nil) == nil)
        #expect(ParallelSharing.inviteURL(page: page, shareLink: URL(string: "https://www.icloud.com/")!, from: nil) == nil)
        #expect(ParallelSharing.inviteURL(page: page, shareLink: URL(string: "https://www.icloud.com/share/")!, from: nil) == nil)
    }

    @Test func anInvitationLinkLeadsBackToItsShare() {
        let page = URL(string: "https://waytrace.cn/join.html?s=0a1B2c3D4e5F6g7H8&n=%E5%B0%8F%E8%93%9D")!
        #expect(ParallelSharing.shareLink(fromInvite: page)?.absoluteString == "https://www.icloud.com/share/0a1B2c3D4e5F6g7H8")
        let china = URL(string: "waytrace://join?s=0a1B2c3D4e5F6g7H8&h=cn")!
        #expect(ParallelSharing.shareLink(fromInvite: china)?.absoluteString == "https://www.icloud.com.cn/share/0a1B2c3D4e5F6g7H8")
    }

    @Test func otherLinksAreNotInvitations() {
        for text in ["https://waytrace.cn/", "https://waytrace.cn/join.html", "https://waytrace.cn/join.html?s=../../x",
                     "https://example.com/join.html?s=0a1B2c3D4e5F6g7H8", "waytrace://other?s=0a1B2c3D4e5F6g7H8",
                     "https://waytrace.cn/join.html?s=short"] {
            #expect(ParallelSharing.shareLink(fromInvite: URL(string: text)!) == nil, "\(text)")
        }
    }

    @Test func thePageAndTheAppAgreeOnALink() {
        for host in ["www.icloud.com", "www.icloud.com.cn"] {
            let share = URL(string: "https://\(host)/share/0a1B2c3D4e5F6g7H8#Title")!
            let invite = ParallelSharing.inviteURL(page: page, shareLink: share, from: "A & B")!
            #expect(ParallelSharing.shareLink(fromInvite: invite)?.absoluteString == "https://\(host)/share/0a1B2c3D4e5F6g7H8")
        }
    }
}
