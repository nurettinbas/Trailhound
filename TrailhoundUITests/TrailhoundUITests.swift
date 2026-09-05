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

final class TrailhoundSmartCategoryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITesting", "-UITesting.smartCategorySeed"]
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

    private var settingsTab: XCUIElement {
        tabButton(identifier: "tab.settings", fallbackLabel: "Settings")
    }

    private var uiTimeout: TimeInterval {
        ProcessInfo.processInfo.environment["CI"] == "true" ? 25 : 15
    }

    private func revealSettingsControl(_ query: XCUIElement) {
        for _ in 0..<10 {
            if query.waitForExistence(timeout: 1), query.isHittable { return }
            if query.exists, !query.isHittable {
                app.swipeDown()
                if query.isHittable { return }
            }
            app.swipeUp()
        }
    }

    func testSmartCategorySettingsToggleHidesWorkHours() {
        XCTAssertTrue(settingsTab.waitForExistence(timeout: uiTimeout))
        settingsTab.tap()

        let toggle = app.switches["settings.smartCategory"]
        revealSettingsControl(toggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(toggle.isHittable, "Smart category toggle must be tappable, not under the tab bar")
        XCTAssertTrue(toggle.isEnabled)

        if (toggle.value as? String) != "1" {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "1")

        let workStart = app.descendants(matching: .any)["settings.smartCategory.workStart"]
        XCTAssertTrue(
            workStart.waitForExistence(timeout: 5),
            "Work-hour start should be visible while suggestions are on"
        )

        toggle.tap()
        if ["1", "On"].contains(toggle.value as? String ?? "") {
            toggle.swipeLeft()
        }

        let rawValue = String(describing: toggle.value)
        let pickersHidden = !app.descendants(matching: .any)["settings.smartCategory.workStart"].waitForExistence(timeout: 3)
        XCTAssertTrue(
            pickersHidden,
            "Work-hour pickers should hide when suggestions are off (toggle value=\(rawValue))"
        )
        XCTAssertFalse(app.descendants(matching: .any)["settings.smartCategory.workEnd"].exists)
    }

    private func element(identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.exists { return button }
        let cell = app.cells[identifier]
        if cell.exists { return cell }
        let other = app.otherElements[identifier]
        if other.exists { return other }
        return button
    }

    private func waitForIdentifier(_ identifier: String) -> Bool {
        if app.buttons[identifier].waitForExistence(timeout: uiTimeout) {
            return true
        }
        if app.cells[identifier].waitForExistence(timeout: 3) {
            return true
        }
        if app.otherElements[identifier].waitForExistence(timeout: 3) {
            return true
        }
        return app.descendants(matching: .any)[identifier].waitForExistence(timeout: 3)
    }

    func testSuggestedCategoryChipAppearsOnTripRow() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(
            waitForIdentifier("trips.row.first.suggested"),
            "Seeded commute trip should be the first row with a pending suggestion"
        )
    }

    func testSwipeAcceptsSuggestedCategory() {
        XCTAssertTrue(tripsTab.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(
            waitForIdentifier("trips.row.first.suggested"),
            "Seeded commute trip should be the first row with a pending suggestion"
        )

        element(identifier: "trips.row.first.suggested").swipeRight()
        let accept = element(identifier: "trips.row.acceptSuggestedCategory")
        if accept.waitForExistence(timeout: 3) {
            accept.tap()
        }

        XCTAssertFalse(waitForIdentifierGone("trips.row.first.suggested"))
        XCTAssertTrue(waitForIdentifier("trips.row.first"))

        let toast = app.staticTexts["Category updated"]
        _ = toast.waitForExistence(timeout: 2)
    }

    private func waitForIdentifierGone(_ identifier: String) -> Bool {
        app.descendants(matching: .any)[identifier].waitForExistence(timeout: 3)
    }
}
