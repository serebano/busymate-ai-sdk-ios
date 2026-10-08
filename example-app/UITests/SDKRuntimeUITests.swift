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
        snapshot("03-sdk-settings-initial")
        mic.tap()
        XCTAssertEqual(mic.value as? String, "0")
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
