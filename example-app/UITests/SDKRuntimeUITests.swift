import XCTest

final class SDKRuntimeUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "ai.busymate.sdk.example")
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 30))
    }
    func snapshot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
    func scrollTo(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTFail("Control not reachable: \(element)")
    }
    func event(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }
    func noPermissionPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertEqual(springboard.alerts.count, 0)
    }
    func testReleasedDemoSettingsGuestRuntime() {
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 30))
        // Keep the initial chat visible through WebKit startup. A WebView
        // shell alone does not prove the hosted page has rendered.
        XCTAssertTrue(app.webViews.firstMatch.buttons["Start voice input"].waitForExistence(timeout: 90))
        noPermissionPrompt()
        snapshot("01-chat-open-no-permission-prompt")
        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(event("Installed identity v2; native microphone enabled").waitForExistence(timeout: 10))
        XCTAssertTrue(event("Chat document loaded").waitForExistence(timeout: 45))
        snapshot("02-real-native-installed-and-webview-load-events")
        app.tabBars.buttons["Settings"].tap()
        let mic = app.switches["Enable tap-triggered OS permission"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        XCTAssertEqual(mic.value as? String, "1")
        scrollTo(mic)
        snapshot("03-sdk-settings-initial")
        // SwiftUI exposes the complete label row as the switch's hit region.
        // Tap the trailing native thumb shown in the runtime screenshot.
        mic.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -25, dy: 0)).tap()
        let switchedOff = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: mic)
        XCTAssertEqual(XCTWaiter.wait(for: [switchedOff], timeout: 5), .completed)
        let apply = app.buttons["Apply and open chat"]
        scrollTo(apply)
        snapshot("04-sdk-lifecycle-controls")
        apply.tap()
        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(event("Installed identity v2; native microphone disabled").waitForExistence(timeout: 10))
        noPermissionPrompt()
        snapshot("05-microphone-disabled-native-event")
        app.tabBars.buttons["Settings"].tap()
        let reset = app.buttons["Reset to guest defaults"]
        scrollTo(reset)
        reset.tap()
        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(event("Demo settings reset to guest defaults").waitForExistence(timeout: 10))
        XCTAssertTrue(event("Installed identity v2; native microphone enabled").exists)
        snapshot("06-reset-guest-native-event")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 10))
        noPermissionPrompt()
        snapshot("07-background-foreground-no-permission-prompt")
    }
}

/// Only the gated permission script enables these tests. Each method runs in a
/// separate invocation after resetting this disposable simulator's permission.
final class FirstTapPermissionUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "ai.busymate.sdk.example")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BUSYMATE_PERMISSION_SUITE"] == "1",
                          "Use the gated test-permissions.sh after the native hosted revision is live")
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }
    override func tearDown() {
        if app.state != .notRunning {
            attach("final-screen", XCUIScreen.main.screenshot())
            // End any virtual media/session immediately; do not tap dictation
            // Stop, which would submit audio for transcription.
            app.terminate()
        }
    }
    private func attach(_ name: String, _ screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func firstTap(_ source: String, grant: Bool) {
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 45))
        let dictation = web.buttons["Start voice input"]
        let voice = web.buttons["Enter voice mode"]
        XCTAssertTrue(dictation.waitForExistence(timeout: 90), "Real hosted dictation must render")
        XCTAssertTrue(voice.waitForExistence(timeout: 15), "Real hosted voice mode must render")
        XCTAssertTrue(dictation.isHittable)
        XCTAssertTrue(voice.isHittable)
        XCTAssertEqual(app.alerts.count, 0, "Opening hosted chat must not request permission")
        XCTAssertEqual(springboard.alerts.count, 0, "Opening hosted chat must not request OS permission")
        attach("\(source)-visible-hosted-chat-before-tap-no-prompt", XCUIScreen.main.screenshot())
        (source == "dictation" ? dictation : voice).tap()

        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "First hosted tap must open the actual iOS dialog")
        let text = alert.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " ")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("microphone"), "Must be the microphone dialog: \(text)")
        XCTAssertTrue(text.contains("Busymate SDK Demo"), "Must name this app, not a website: \(text)")
        attach("\(source)-actual-ios-microphone-dialog", XCUIScreen.main.screenshot())
        let accepted = grant ? ["Allow", "OK"] : ["Don't Allow", "Don’t Allow"]
        let choice = alert.buttons.matching(NSPredicate(format: "label IN %@", accepted as NSArray)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alert)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        attach("\(source)-ios-\(grant ? "grant" : "deny")-chosen", XCUIScreen.main.screenshot())
        app.terminate()
    }
    func testDictationGrant() { firstTap("dictation", grant: true) }
    func testDictationDeny() { firstTap("dictation", grant: false) }
    func testVoiceGrant() { firstTap("voice", grant: true) }
    func testVoiceDeny() { firstTap("voice", grant: false) }
}
