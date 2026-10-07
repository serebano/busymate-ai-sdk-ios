import XCTest
#if canImport(BusymateSDKExample)
@testable import BusymateSDKExample
#else
@testable import DemoConfiguration
#endif

final class DemoConfigurationTests: XCTestCase {
    func testDefaultLoadsRealGuestChatAndExactOrigin() throws {
        let config = DemoConfiguration()
        let valid = try config.validated()
        XCTAssertEqual(valid.chatURL.absoluteString, "https://busymate.ai/support/busyproxy?channel=ios")
        XCTAssertEqual(valid.origins, ["https://busymate.ai"])
        XCTAssertFalse(config.signedIn)
        XCTAssertNil(valid.backendURL)
    }
    func testInsecureChatAndEmbeddedCredentialsAreRefused() {
        for url in ["http://busymate.ai/support/busyproxy", "https://user:password@busymate.ai/support/busyproxy"] {
            var config = DemoConfiguration(); config.chatURL = url
            XCTAssertThrowsError(try config.validated())
        }
    }
    func testOriginsRejectWildcardsPathsAndOtherTenants() {
        for origin in ["https://*.busymate.ai", "https://busymate.ai/path", "https://other.busymate.ai"] {
            var config = DemoConfiguration(); config.origins = origin
            XCTAssertThrowsError(try config.validated())
        }
    }
    func testDefaultPortAndHostCaseNormalize() throws {
        var config = DemoConfiguration(); config.origins = "https://BUSYMATE.AI:443"
        XCTAssertEqual(try config.validated().origins, ["https://busymate.ai"])
    }
    func testIdentifiedModeCannotPretendToAuthenticate() {
        var config = DemoConfiguration(); config.signedIn = true
        XCTAssertThrowsError(try config.validated())
        config.accountID = "actual-account"
        XCTAssertThrowsError(try config.validated())
        config.mintURL = "http://backend.example/mint"
        XCTAssertThrowsError(try config.validated())
    }
    func testUnregisteredAuthCallbackSchemeIsRefused() {
        var config = DemoConfiguration(); config.authenticationOpen = true; config.callbackScheme = "invented"
        XCTAssertThrowsError(try config.validated())
    }
    func testMintRequestPreservesSDKNonceAndTrustedFieldsWithoutCredentials() throws {
        let payload = DemoMintPayload(nonce: "request-nonce", audience: "audience", reason: "refresh",
                                      assistant: "busyproxy", origin: "https://busymate.ai")
        let request = try payload.request(to: URL(string: "https://backend.example/mint")!)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: String]
        XCTAssertEqual(body, ["nonce": "request-nonce", "aud": "audience", "reason": "refresh", "assistant": "busyproxy", "origin": "https://busymate.ai"])
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
    }
    func testCallbackFactoriesReturnNilWhenDisabledAndOnlyHandleClose() {
        var closed = 0
        XCTAssertNil(DemoCallbacks.action(enabled: false, close: { closed += 1 }, ready: {}))
        XCTAssertNil(DemoCallbacks.close(enabled: false, perform: { closed += 1 }))
        let action = DemoCallbacks.action(enabled: true, close: { closed += 1 }, ready: {})!
        XCTAssertFalse(action("unknown", [:]))
        XCTAssertFalse(action("ready", [:]))
        XCTAssertTrue(action("close", [:]))
        XCTAssertEqual(closed, 1)
    }
    func testBackendSessionTokenIsHeaderOnlyAndRejectsHeaderInjection() throws {
        let payload = DemoMintPayload(nonce: "expected", audience: nil, reason: nil,
                                      assistant: "busyproxy", origin: "https://busymate.ai")
        let url = URL(string: "https://backend.example/mint")!
        let request = try payload.request(to: url, sessionToken: "existing-session")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer existing-session")
        XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains("existing-session"))
        XCTAssertThrowsError(try payload.request(to: url, sessionToken: "invalid\r\nheader"))
    }
    #if os(macOS)
    func testRealMintTransportDoesNotFollowAuthenticatedRedirect() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("redirect-fixture.py")
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-u", fixture.path]
        process.standardOutput = output
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let ports = try JSONSerialization.jsonObject(with: output.fileHandleForReading.availableData) as! [String: Int]
        let endpoint = URL(string: "http://127.0.0.1:\(ports["origin"]!)/mint")!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer regression-fixture", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        let (_, response) = try await session.data(for: request, delegate: NoMintRedirects())
        XCTAssertEqual((response as! HTTPURLResponse).statusCode, 302)
        let (countData, _) = try await session.data(from: endpoint)
        let counts = try JSONSerialization.jsonObject(with: countData) as! [String: Int]
        XCTAssertEqual(counts["targetHits"], 0, "The alternate endpoint must never receive authenticated traffic")
    }
    #endif
    func testMintRejectsUncorrelatedNonceAndUnauthorizedFallsBackToGuest() throws {
        let payload = DemoMintPayload(nonce: "expected", audience: nil, reason: nil,
                                      assistant: "busyproxy", origin: "https://busymate.ai")
        XCTAssertNil(try payload.decode(Data(), status: 401))
        XCTAssertThrowsError(try payload.decode(Data(), status: 302))
        XCTAssertThrowsError(try payload.decode(Data(#"{"token":"assertion","nonce":"other"}"#.utf8), status: 200))
        let result = try payload.decode(Data(#"{"token":"assertion","nonce":"expected"}"#.utf8), status: 200)
        XCTAssertEqual(result?.nonce, "expected")
    }
}
