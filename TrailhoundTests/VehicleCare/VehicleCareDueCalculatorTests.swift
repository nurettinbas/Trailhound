import XCTest
@testable import Trailhound

final class VehicleCareDueCalculatorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testUpcomingTodayOverdueAndNoDate() {
        var components = DateComponents(year: 2026, month: 8, day: 8)
        let today = calendar.date(from: components)!

        components.day = 15
        let upcoming = calendar.date(from: components)!
        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(nextDueDate: upcoming, today: today, calendar: calendar),
            .upcoming(daysLeft: 7)
        )

        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(nextDueDate: today, today: today, calendar: calendar),
            .dueToday
        )

        components.day = 5
        let overdue = calendar.date(from: components)!
        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(nextDueDate: overdue, today: today, calendar: calendar),
            .overdue(days: 3)
        )

        XCTAssertEqual(
            VehicleCareDueCalculator.dueState(nextDueDate: nil, today: today, calendar: calendar),
            .noDate
        )
    }

    func testRollForwardMonthsAndYears() {
        let completed = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        let nextMonth = VehicleCareDueCalculator.nextDueDateAfterCompletion(
            completedOn: completed,
            intervalKind: .everyMonths,
            intervalMonths: 12,
            calendar: calendar
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: nextMonth!),
            DateComponents(year: 2027, month: 1, day: 10)
        )

        let nextYear = VehicleCareDueCalculator.nextDueDateAfterCompletion(
            completedOn: completed,
            intervalKind: .everyYears,
            intervalMonths: 24,
            calendar: calendar
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: nextYear!),
            DateComponents(year: 2028, month: 1, day: 10)
        )

        XCTAssertNil(
            VehicleCareDueCalculator.nextDueDateAfterCompletion(
                completedOn: completed,
                intervalKind: .none,
                intervalMonths: nil,
                calendar: calendar
            )
        )
    }

    func testDefaultReminderOffsets() {
        XCTAssertEqual(VehicleScheduleKind.service.defaultReminderOffsets, [30, 7])
        XCTAssertEqual(VehicleScheduleKind.inspection.defaultReminderOffsets, [30, 7])
        XCTAssertEqual(VehicleScheduleKind.trafficInsurance.defaultReminderOffsets, [7])
        XCTAssertEqual(VehicleScheduleKind.casco.defaultReminderOffsets, [7])
    }

    func testUrgencyBandMapping() {
        XCTAssertEqual(VehicleCareUrgencyStyle.band(for: .overdue(days: 2)), .alert)
        XCTAssertEqual(VehicleCareUrgencyStyle.band(for: .dueToday), .warning)
        XCTAssertEqual(VehicleCareUrgencyStyle.band(for: .upcoming(daysLeft: 30)), .warning)
        XCTAssertEqual(VehicleCareUrgencyStyle.band(for: .upcoming(daysLeft: 7)), .warning)
        XCTAssertNil(VehicleCareUrgencyStyle.band(for: .upcoming(daysLeft: 31)))
        XCTAssertNil(VehicleCareUrgencyStyle.band(for: .noDate))
        XCTAssertNil(VehicleCareUrgencyStyle.chipText(for: .upcoming(daysLeft: 45)))
        XCTAssertNotNil(VehicleCareUrgencyStyle.chipText(for: .upcoming(daysLeft: 5)))
    }

    func testEncodeDecodeOffsets() {
        let raw = VehicleSchedule.encodeOffsets([30, 7])
        XCTAssertEqual(raw, "30,7")
        XCTAssertEqual(VehicleSchedule.decodeOffsets(raw), [30, 7])
    }
}
