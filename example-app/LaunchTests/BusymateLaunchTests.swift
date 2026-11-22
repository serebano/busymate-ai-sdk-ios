import XCTest
@testable import BusymateLaunch

final class BusymateLaunchTests: XCTestCase {
    private let base = URL(string: "https://busymate.ai/chat/w/demos?channel=ios")!

    func testAppendsVersionAndHostAppAndKeepsChannel() {
        let url = BusymateLaunch.launchURL(base, sdkVersion: "1.0.5", hostAppId: "ai.busymate.sample")
        XCTAssertEqual(url.absoluteString, "https://busymate.ai/chat/w/demos?channel=ios&sdkVersion=1.0.5&hostAppId=ai.busymate.sample")
    }
    func testPublicEntryPointUsesTheSDKVersionConstant() {
        let url = BusymateLaunch.chatURL(base, hostAppId: "ai.busymate.sample")
        XCTAssertTrue(url.absoluteString.contains("sdkVersion=" + BusymateLaunch.sdkVersion))
        XCTAssertTrue(BusymateLaunch.isValidSDKVersion(BusymateLaunch.sdkVersion))
    }
    func testVersionIsEncodedAndPrereleaseKept() {
        let url = BusymateLaunch.launchURL(base, sdkVersion: "1.1.0-beta.2+7", hostAppId: nil)
        XCTAssertEqual(url.absoluteString, "https://busymate.ai/chat/w/demos?channel=ios&sdkVersion=1.1.0-beta.2%2B7")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.last?.value, "1.1.0-beta.2+7")
    }
    func testHostAppIdLeftOutUnlessItMatches() {
        for bad in ["", "a", "1abc.def", "ai busymate", "ai.busymate&x=1", String(repeating: "a", count: 129)] {
            let url = BusymateLaunch.launchURL(base, sdkVersion: "1.0.5", hostAppId: bad)
            XCTAssertFalse(url.absoluteString.contains("hostAppId"), bad)
        }
        XCTAssertTrue(BusymateLaunch.launchURL(base, sdkVersion: "1.0.5", hostAppId: nil).absoluteString.hasSuffix("sdkVersion=1.0.5"))
        XCTAssertTrue(BusymateLaunch.isValidHostAppID(String(repeating: "a", count: 128)))
    }
    func testInvalidVersionIsLeftOutAndNoQueryBaseGetsOne() {
        XCTAssertEqual(BusymateLaunch.launchURL(base, sdkVersion: "bad version", hostAppId: nil), base)
        let bare = URL(string: "https://busymate.ai/chat/w/demos")!
        XCTAssertEqual(BusymateLaunch.launchURL(bare, sdkVersion: "1.0.5", hostAppId: nil).absoluteString, "https://busymate.ai/chat/w/demos?sdkVersion=1.0.5")
    }
    func testEarlierLaunchParametersAreReplacedAndFragmentKept() {
        let old = URL(string: "https://busymate.ai/chat/w/demos?sdkVersion=9&channel=ios&hostAppId=evil#x")!
        let url = BusymateLaunch.launchURL(old, sdkVersion: "1.0.5", hostAppId: "ai.busymate.sample")
        XCTAssertEqual(url.absoluteString, "https://busymate.ai/chat/w/demos?channel=ios&sdkVersion=1.0.5&hostAppId=ai.busymate.sample#x")
    }
}
