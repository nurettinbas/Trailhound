import XCTest
@testable import Trailhound

@MainActor
final class SmartCategorySettingsTests: XCTestCase {
    func testSuggestionsDefaultOnWhenKeyMissing() {
        let defaults = UserDefaults(suiteName: "test.trailhound.smartcat.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        XCTAssertTrue(settings.smartCategorySuggestionsEnabled)
    }

    func testSuggestionsCanBeDisabled() {
        let defaults = UserDefaults(suiteName: "test.trailhound.smartcat.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        settings.smartCategorySuggestionsEnabled = false
        XCTAssertFalse(settings.smartCategorySuggestionsEnabled)
    }

    func testWorkHoursDefaultAndClamp() {
        let defaults = UserDefaults(suiteName: "test.trailhound.smartcat.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)
        XCTAssertEqual(settings.workHourStart, 9)
        XCTAssertEqual(settings.workHourEnd, 18)

        settings.workHourStart = 99
        settings.workHourEnd = 99
        XCTAssertEqual(settings.workHourStart, 23)
        XCTAssertEqual(settings.workHourEnd, 23)
    }
}

final class SmartCategoryToastTests: XCTestCase {
    func testCategoryAcceptedMessageIsDistinctFromJournalTitleRequired() {
        XCTAssertEqual(ToastKind.categoryAccepted.message, L10n.toastCategoryAccepted)
        XCTAssertEqual(ToastKind.journalTitleRequired.message, L10n.journalTitleRequired)
        XCTAssertNotEqual(ToastKind.categoryAccepted.message, ToastKind.journalTitleRequired.message)
    }
}
