import XCTest
@testable import BusymateUnread

/// The checks every message from the chat page must pass before the app acts on it.
final class BusymateBridgeValidationTests: XCTestCase {
    private let token = "v1.eyJ0IjoiYWNtZSJ9.c2lnbmF0dXJlLXNpZ25hdHVyZQ"

    func testUnreadMessageIsRead() {
        let message = BusymateChatMessage.parse([
            "type": "support.chat.v1.unread", "n": 2, "t": "Still thinking about the blue one?", "at": "2026-11-27T09:30:00.000Z"] as [String: Any])
        guard case .unread(let unread)? = message else { return XCTFail("expected unread") }
        XCTAssertEqual(unread.count, 2)
        XCTAssertEqual(unread.preview, "Still thinking about the blue one?")
        XCTAssertEqual(unread.at, ISO8601DateFormatter().date(from: "2026-11-27T09:30:00Z"))
        XCTAssertEqual(unread.badgeText, "2")
    }
    func testUnreadAcceptsABareCountNullsAndAJSONString() {
        XCTAssertEqual(BusymateChatMessage.parse(["type": "support.chat.v1.unread", "n": 0] as [String: Any]), .unread(.none))
        XCTAssertEqual(BusymateChatMessage.parse(["type": "support.chat.v1.unread", "n": 3.0, "t": NSNull(), "at": NSNull()] as [String: Any]),
                       .unread(BusymateUnread(count: 3)))
        XCTAssertEqual(BusymateChatMessage.parse(#"{"type":"support.chat.v1.unread","n":1,"t":"Hi","at":"2026-11-27T09:30:00Z"}"#),
                       .unread(BusymateUnread(count: 1, preview: "Hi", at: ISO8601DateFormatter().date(from: "2026-11-27T09:30:00Z"))))
    }
    func testUnreadPreviewIsOneLineAndAtMost80Characters() {
        let long = String(repeating: "a", count: 200)
        guard case .unread(let cut)? = BusymateChatMessage.parse(["type": "support.chat.v1.unread", "n": 1, "t": long] as [String: Any]) else { return XCTFail() }
        XCTAssertEqual(cut.preview.count, 80)
        guard case .unread(let flat)? = BusymateChatMessage.parse(["type": "support.chat.v1.unread", "n": 1, "t": "  one\ntwo\u{0007}three  "] as [String: Any]) else { return XCTFail() }
        XCTAssertEqual(flat.preview, "one two three")
    }
    func testMalformedUnreadIsDropped() {
        let bad: [[String: Any]] = [
            ["type": "support.chat.v1.unread"],
            ["type": "support.chat.v1.unread", "n": "2"],
            ["type": "support.chat.v1.unread", "n": true],
            ["type": "support.chat.v1.unread", "n": -1],
            ["type": "support.chat.v1.unread", "n": 1.5],
            ["type": "support.chat.v1.unread", "n": 2_000_000],
            ["type": "support.chat.v1.unread", "n": 1, "t": 7],
            ["type": "support.chat.v1.unread", "n": 1, "t": ["x"]],
            ["type": "support.chat.v1.unread", "n": 1, "at": 1_795_000_000],
            ["type": "support.chat.v1.unread", "n": 1, "at": "yesterday"],
        ]
        for object in bad { XCTAssertNil(BusymateChatMessage.parse(object), "\(object)") }
    }
    func testIdentityMessageIsReadAndBadTokensAreDropped() {
        XCTAssertEqual(BusymateChatMessage.parse(["type": "support.chat.v1.identity", "v": token] as [String: Any]), .identity(token: token))
        for bad in ["", "short", "has space in the token value", "quote\"in-the-token-value", "new\nline-in-the-token-value",
                    "<script>alert(1)</script>", String(repeating: "a", count: 2049)] {
            XCTAssertNil(BusymateChatMessage.parse(["type": "support.chat.v1.identity", "v": bad] as [String: Any]), bad)
        }
        XCTAssertNil(BusymateChatMessage.parse(["type": "support.chat.v1.identity", "v": 42] as [String: Any]))
        XCTAssertNil(BusymateChatMessage.parse(["type": "support.chat.v1.identity"] as [String: Any]))
    }
    func testUnknownTypesAndShapesAreDropped() {
        XCTAssertNil(BusymateChatMessage.parse(["type": "support.chat.v1.open"] as [String: Any]), "open goes app → page only")
        XCTAssertNil(BusymateChatMessage.parse(["type": "support.chat.v2.unread", "n": 1] as [String: Any]))
        XCTAssertNil(BusymateChatMessage.parse(["type": "busymate.microphone.v1.request", "id": "1"] as [String: Any]))
        XCTAssertNil(BusymateChatMessage.parse(["n": 1] as [String: Any]))
        XCTAssertNil(BusymateChatMessage.parse(["type": 5, "n": 1] as [String: Any]))
        XCTAssertNil(BusymateChatMessage.parse(42))
        XCTAssertNil(BusymateChatMessage.parse(["support.chat.v1.unread"]))
        XCTAssertNil(BusymateChatMessage.parse("not json"))
        XCTAssertNil(BusymateChatMessage.parse("[1,2]"))
        XCTAssertNil(BusymateChatMessage.parse(#"{"type":"support.chat.v1.unread","n":1,"t":""# + String(repeating: "x", count: 5000) + #""}"#), "over 4 KB")
        var wide: [String: Any] = ["type": "support.chat.v1.unread", "n": 1]
        for index in 0..<20 { wide["k\(index)"] = index }
        XCTAssertNil(BusymateChatMessage.parse(wide), "too many keys")
    }
    func testOpenScriptIsAConstantThatPostsToThePagesOwnOrigin() {
        XCTAssertEqual(BusymateChatMessage.openScript, #"window.postMessage({type:"support.chat.v1.open"},location.origin);"#)
    }

    // Origins: only Busymate's chat origins for the assistant and the host's exact https origins are heard.
    func testAllowedOriginsAreExact() {
        let allowed = BusymateOrigins.allowed(assistant: "acme", chatURL: URL(string: "https://busymate.ai/chat/w/acme?channel=ios"),
                                              extra: ["https://Support.Acme.com/", "https://help.acme.com:8443", "http://plain.acme.com", "https://*.acme.com", "https://acme.com/path"])
        XCTAssertEqual(allowed, ["https://busymate.ai", "https://acme.busymate.ai", "https://support.acme.com", "https://help.acme.com:8443"])
    }
    func testFrameOriginFromWebKitParts() {
        XCTAssertEqual(BusymateOrigins.origin(scheme: "https", host: "busymate.ai", port: 0), "https://busymate.ai")
        XCTAssertEqual(BusymateOrigins.origin(scheme: "https", host: "Acme.Busymate.ai", port: 443), "https://acme.busymate.ai")
        XCTAssertEqual(BusymateOrigins.origin(scheme: "https", host: "help.acme.com", port: 8443), "https://help.acme.com:8443")
        XCTAssertNil(BusymateOrigins.origin(scheme: "http", host: "busymate.ai", port: 0))
        XCTAssertNil(BusymateOrigins.origin(scheme: "https", host: "", port: 0), "about:blank / data: frames have no host")
        XCTAssertNil(BusymateOrigins.origin(scheme: "file", host: "", port: 0))
    }
    func testOtherTenantsAndLookalikesAreNotAllowed() {
        let allowed = BusymateOrigins.allowed(assistant: "acme", chatURL: nil, extra: [])
        for other in ["https://other.busymate.ai", "https://busymate.ai.evil.com", "https://evil.com", "https://xbusymate.ai", "https://acme.busymate.ai:8443"] {
            XCTAssertFalse(allowed.contains(other), other)
        }
        XCTAssertNil(BusymateOrigins.origin(of: URL(string: "https://user:pw@busymate.ai/chat")!), "credentials in the URL")
        XCTAssertEqual(BusymateOrigins.allowed(assistant: "Not A Slug", chatURL: nil, extra: []), ["https://busymate.ai"])
    }
}

/// The visitor token store: validated on the way in and out, one entry per assistant.
final class BusymateTokenStoreTests: XCTestCase {
    private let token = "v1.eyJ0IjoiYWNtZSJ9.c2lnbmF0dXJlLXNpZ25hdHVyZQ"
    private var service = ""
    private var store: BusymateKeychainTokenStore!

    /// The real Keychain round trip runs on a developer Mac. The CI runner runs every job inside a sandbox
    /// where a keychain call waits for a dialog nobody can answer (sdk-ios run 45978810109 hung there), so
    /// it is skipped under GitHub Actions; `BUSYMATE_KEYCHAIN_TESTS=1` forces it, `=0` skips it anywhere.
    private static var keychainAllowed: Bool {
        let env = ProcessInfo.processInfo.environment
        if let forced = env["BUSYMATE_KEYCHAIN_TESTS"] { return forced == "1" }
        return env["GITHUB_ACTIONS"] == nil
    }

    override func setUpWithError() throws {
        service = "ai.busymate.sdk.visitor.tests." + UUID().uuidString
        store = nil
        guard Self.keychainAllowed else { return }
        let candidate = BusymateKeychainTokenStore(service: service)
        if candidate.save(token, for: "probe") { candidate.delete(for: "probe"); store = candidate }
    }
    override func tearDown() {
        guard store != nil else { return }
        for assistant in ["acme", "other", "probe"] { BusymateKeychainTokenStore(service: service).delete(for: assistant) }
    }

    private func usableStore() throws -> BusymateKeychainTokenStore {
        guard let store else { throw XCTSkip("no usable keychain on this host") }
        return store
    }

    func testRoundTripUpdateAndDelete() throws {
        let store = try usableStore()
        XCTAssertNil(store.token(for: "acme"))
        XCTAssertTrue(store.save(token, for: "acme"))
        XCTAssertEqual(store.token(for: "acme"), token)
        let renewed = token + ".renewed"
        XCTAssertTrue(store.save(renewed, for: "acme"), "a renewal replaces the entry")
        XCTAssertEqual(store.token(for: "acme"), renewed)
        XCTAssertTrue(store.delete(for: "acme"))
        XCTAssertNil(store.token(for: "acme"))
        XCTAssertTrue(store.delete(for: "acme"), "deleting nothing is fine")
    }
    func testOneEntryPerAssistant() throws {
        let store = try usableStore()
        XCTAssertTrue(store.save(token, for: "acme"))
        XCTAssertNil(store.token(for: "other"), "another workspace never reads this token")
        XCTAssertTrue(store.save(token + ".other", for: "other"))
        XCTAssertEqual(store.token(for: "acme"), token)
    }
    /// Refusals happen before any keychain call, so this runs everywhere.
    func testInvalidTokensAndAssistantsAreRefused() {
        let store = BusymateKeychainTokenStore(service: service)
        XCTAssertFalse(store.save("short", for: "acme"))
        XCTAssertFalse(store.save("has space in the token value", for: "acme"))
        XCTAssertFalse(store.save(token, for: "Not A Slug"))
        XCTAssertFalse(store.save(token, for: ""))
        XCTAssertNil(store.token(for: "Not A Slug"), "refused before any keychain call")
    }
    func testDefaultServiceName() {
        XCTAssertEqual(BusymateKeychainTokenStore().service, "ai.busymate.sdk.visitor")
    }
}

/// `POST /api/chat/unread` and its answers.
final class BusymateUnreadRequestTests: XCTestCase {
    private let token = "v1.eyJ0IjoiYWNtZSJ9.c2lnbmF0dXJlLXNpZ25hdHVyZQ"

    func testRequestShape() throws {
        let request = try XCTUnwrap(BusymateUnreadRequest.make(origin: "https://busymate.ai", assistant: "acme", token: token, sdkVersion: "9.9.9"))
        XCTAssertEqual(request.url?.absoluteString, "https://busymate.ai/api/chat/unread")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/plain")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Busymate-SDK"), "ios/9.9.9")
        XCTAssertFalse(request.httpShouldHandleCookies)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["a": "acme", "v": token])
        XCTAssertFalse(request.url!.absoluteString.contains(token), "the token is never in the URL")
    }
    func testNoRequestWithoutAValidOriginSlugOrToken() {
        XCTAssertNil(BusymateUnreadRequest.make(origin: "http://busymate.ai", assistant: "acme", token: token, sdkVersion: "1"))
        XCTAssertNil(BusymateUnreadRequest.make(origin: "https://busymate.ai/path", assistant: "acme", token: token, sdkVersion: "1"))
        XCTAssertNil(BusymateUnreadRequest.make(origin: "https://busymate.ai", assistant: "Not A Slug", token: token, sdkVersion: "1"))
        XCTAssertNil(BusymateUnreadRequest.make(origin: "https://busymate.ai", assistant: "acme", token: "short", sdkVersion: "1"))
    }
    func testAnswers() {
        XCTAssertEqual(BusymateUnreadRequest.answer(status: 204, data: Data()), BusymateUnread.none)
        let ok = Data(#"{"n":2,"t":"Still thinking about the blue one?","at":"2026-11-27T09:30:00.000Z"}"#.utf8)
        XCTAssertEqual(BusymateUnreadRequest.answer(status: 200, data: ok),
                       BusymateUnread(count: 2, preview: "Still thinking about the blue one?", at: ISO8601DateFormatter().date(from: "2026-11-27T09:30:00Z")))
        XCTAssertEqual(BusymateUnreadRequest.answer(status: 200, data: Data(#"{"n":1,"t":"Hi","at":null}"#.utf8)), BusymateUnread(count: 1, preview: "Hi"))
        // No answer (keep what we know): errors, redirects, junk.
        for status in [301, 302, 400, 401, 404, 429, 500, 503] { XCTAssertNil(BusymateUnreadRequest.answer(status: status, data: ok), "\(status)") }
        XCTAssertNil(BusymateUnreadRequest.answer(status: 200, data: Data("<html>".utf8)))
        XCTAssertNil(BusymateUnreadRequest.answer(status: 200, data: Data(#"{"n":"2"}"#.utf8)))
        XCTAssertNil(BusymateUnreadRequest.answer(status: 200, data: Data(#"{"type":"support.chat.v1.identity","v":"aaaaaaaaaaaaaaaaaaaa","n":"x"}"#.utf8)),
                     "the body cannot choose its own type")
    }
}

/// Badge and bubble: dismissing the bubble leaves the message unread.
final class BusymateUnreadStateTests: XCTestCase {
    private let first = BusymateUnread(count: 1, preview: "Still thinking about the blue one?", at: Date(timeIntervalSince1970: 1_795_000_000))

    func testBadgeText() {
        XCTAssertNil(BusymateUnread.none.badgeText)
        XCTAssertEqual(BusymateUnread(count: 7).badgeText, "7")
        XCTAssertEqual(BusymateUnread(count: 99).badgeText, "99")
        XCTAssertEqual(BusymateUnread(count: 100).badgeText, "99+")
        XCTAssertEqual(BusymateUnread(count: -3), .none)
        XCTAssertEqual(BusymateUnread(count: 0, preview: "x", at: Date()), .none, "nothing unread carries no text")
    }
    func testDismissLeavesTheCountAndHidesOnlyTheBubble() {
        var state = BusymateUnreadState()
        XCTAssertTrue(state.apply(first))
        XCTAssertEqual(state.teaser, first)
        state.dismissTeaser()
        XCTAssertNil(state.teaser)
        XCTAssertEqual(state.unread.count, 1, "the message is still unread")
        XCTAssertFalse(state.apply(first), "the same answer again changes nothing")
        XCTAssertNil(state.teaser, "and does not bring the bubble back")
    }
    func testANewerMessageTeasesAgain() {
        var state = BusymateUnreadState()
        state.apply(first)
        state.dismissTeaser()
        let second = BusymateUnread(count: 2, preview: "We saved your cart.", at: Date(timeIntervalSince1970: 1_795_003_600))
        XCTAssertTrue(state.apply(second))
        XCTAssertEqual(state.teaser, second)
    }
    func testDismissalSurvivesARelaunchAndClearsWhenSeen() {
        var state = BusymateUnreadState()
        state.apply(first)
        state.dismissTeaser()
        var relaunched = BusymateUnreadState(dismissedKey: state.dismissedKey)
        relaunched.apply(first)
        XCTAssertNil(relaunched.teaser)
        XCTAssertEqual(relaunched.unread, first)
        XCTAssertTrue(relaunched.apply(.none))
        XCTAssertNil(relaunched.dismissedKey)
        XCTAssertNil(relaunched.teaser)
    }
    func testABareCountKeepsThePreviewWeHave() {
        var state = BusymateUnreadState()
        state.apply(first)
        XCTAssertFalse(state.apply(BusymateUnread(count: 1)))
        XCTAssertEqual(state.unread, first)
        XCTAssertTrue(state.apply(BusymateUnread(count: 2)), "a different count is news")
        XCTAssertEqual(state.unread.count, 2)
    }
    func testDismissWithNothingUnreadDoesNothing() {
        var state = BusymateUnreadState()
        state.dismissTeaser()
        XCTAssertNil(state.dismissedKey)
    }
}
