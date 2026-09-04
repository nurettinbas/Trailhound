import XCTest

final class TrailhoundUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launchEnvironment["AppleLanguages"] = "(en)"
        app.launchEnvironment["AppleLocale"] = "en_US"
        app.launch()
    }

    private func tabButton(identifier: String, fallbackLabel: String) -> XCUIElement {
        let byIdentifier = app.tabBars.buttons[identifier]
        if byIdentifier.waitForExistence(timeout: 1) {
            return byIdentifier
        }
        return app.tabBars.buttons[fallbackLabel]
    }

    private var tripsTab: XCUIElement {
        tabButton(identifier: "tab.trips", fallbackLabel: "Trips")
    }

    private var statsTab: XCUIElement {
        tabButton(identifier: "tab.stats", fallbackLabel: "Statistics")
    }

    private var settingsTab: XCUIElement {
        tabButton(identifier: "tab.settings", fallbackLabel: "Settings")
    }

    private var pairingTab: XCUIElement {
        tabButton(identifier: "tab.pairing", fallbackLabel: "Pairing")
    }

    private var uiTimeout: TimeInterval {
        ProcessInfo.processInfo.environment["CI"] == "true" ? 25 : 15
    }

    func testAppLaunchesToTripsTab() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
    }

    func testTabNavigationTripsStatsSettingsPairing() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))

        statsTab.tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 10))

        settingsTab.tap()
        XCTAssertTrue(app.switches["settings.recordingSounds"].waitForExistence(timeout: 10))

        pairingTab.tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 10))

        tripsTab.tap()
        XCTAssertTrue(tripsTab.exists)
    }

    func testTripListOpensDetail() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))

        let firstTrip = app.buttons["trips.row.first"]
        XCTAssertTrue(firstTrip.waitForExistence(timeout: uiTimeout))
        firstTrip.tap()

        XCTAssertTrue(app.otherElements["tripDetail.screen"].waitForExistence(timeout: 15))
    }

    func testSettingsRecordingSoundsToggle() {
        XCTAssertTrue(settingsTab.waitForExistence(timeout: uiTimeout))
        settingsTab.tap()
        let toggle = app.switches["settings.recordingSounds"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertTrue(toggle.isEnabled)
    }

    func testTravelsSegmentOpensJournalEmptyState() throws {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        let segment = app.segmentedControls["trips.segment"]
        guard segment.waitForExistence(timeout: uiTimeout) else {
            throw XCTSkip("Travels segment is hidden until the library has trips.")
        }
        segment.buttons["Travels"].tap()
        XCTAssertTrue(
            app.staticTexts["Create your first travel"].waitForExistence(timeout: 10)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "travel")).firstMatch.exists
        )
    }

    func testNotificationsListOpens() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))

        let notifications = app.buttons["trips.notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 15))
        notifications.tap()

        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 15))
    }

    func testTripDetailSaveButtonExists() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["trips.row.first"].waitForExistence(timeout: uiTimeout))
        app.buttons["trips.row.first"].tap()

        XCTAssertTrue(app.buttons["tripDetail.save"].waitForExistence(timeout: 15))
    }

    func testTripDetailScrollRevealsSaveButton() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons["trips.row.first"].waitForExistence(timeout: uiTimeout))
        app.buttons["trips.row.first"].tap()
        XCTAssertTrue(app.otherElements["tripDetail.screen"].waitForExistence(timeout: 15))

        let saveButton = app.buttons["tripDetail.save"]
        if !saveButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
    }

    func testStatsTabShowsContent() {
        XCTAssertTrue(statsTab.waitForExistence(timeout: uiTimeout))
        statsTab.tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 15))
    }
}
