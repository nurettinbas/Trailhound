import SwiftData
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

@MainActor
final class SmartCategorySeedTests: XCTestCase {
    func testSeededCommuteIsNewestRowWithPendingSuggestion() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let older = PreviewData.sampleTrip
        context.insert(older)
        for point in older.points {
            context.insert(point)
        }

        UITestSupport.seedSmartCategoryFixtures(in: context)
        try context.save()

        var descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let trips = try context.fetch(descriptor)
        let first = try XCTUnwrap(trips.first)
        XCTAssertEqual(first.id, UITestSupport.smartCategorySeedTripID)
        XCTAssertTrue(first.hasPendingCategorySuggestion)
        XCTAssertGreaterThan(first.startedAt, older.startedAt)

        UITestSupport.seedSmartCategoryFixtures(in: context)
        try context.save()
        descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let refreshed = try XCTUnwrap(try context.fetch(descriptor).first)
        XCTAssertEqual(refreshed.id, UITestSupport.smartCategorySeedTripID)
        XCTAssertTrue(refreshed.hasPendingCategorySuggestion)
    }
}

final class SmartCategoryToastTests: XCTestCase {
    func testCategoryAcceptedMessageIsDistinctFromJournalTitleRequired() {
        XCTAssertEqual(ToastKind.categoryAccepted.message, L10n.toastCategoryAccepted)
        XCTAssertEqual(ToastKind.journalTitleRequired.message, L10n.journalTitleRequired)
        XCTAssertNotEqual(ToastKind.categoryAccepted.message, ToastKind.journalTitleRequired.message)
    }
}
