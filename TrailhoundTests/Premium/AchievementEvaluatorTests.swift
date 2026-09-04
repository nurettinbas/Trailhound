import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class AchievementEvaluatorTests: XCTestCase {
    func testBusinessLegacyAndUUIDCountTowardTen() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        for index in 0..<10 {
            let trip = Trip(
                startedAt: Date().addingTimeInterval(Double(-3600 * (10 - index))),
                endedAt: Date().addingTimeInterval(Double(-3600 * (9 - index))),
                distanceMeters: 1_000,
                category: index < 5 ? .business : .personal
            )
            if index >= 5 {
                trip.categoryID = BuiltInCategory.businessID.uuidString
            }
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()
        let displays = AchievementEvaluator.displays(in: context)
        let badge = displays.first { $0.id == .business10 }
        XCTAssertEqual(badge?.currentValue ?? 0, 10, accuracy: 0.1)
        XCTAssertNotNil(badge?.unlockedAt)
    }

    func testStreakCountsConsecutiveCalendarDaysAcrossMidnight() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let trip = Trip(
                startedAt: day.addingTimeInterval(8 * 3600),
                endedAt: day.addingTimeInterval(9 * 3600),
                distanceMeters: 2_000
            )
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()
        XCTAssertEqual(AchievementEvaluator.currentStreakDays(in: context, now: today.addingTimeInterval(12 * 3600), calendar: calendar), 7)
        let streak = AchievementEvaluator.displays(in: context).first { $0.id == .streak7 }
        XCTAssertNotNil(streak?.unlockedAt)
    }

    func testAutoDeleteDoesNotRevokeUnlock() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 120_000
        )
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()
        XCTAssertNotNil(AchievementEvaluator.displays(in: context).first { $0.id == .distance100 }?.unlockedAt)

        TripRollupService.remove(trip, in: context)
        context.delete(trip)
        try context.save()
        let badge = AchievementEvaluator.displays(in: context).first { $0.id == .distance100 }
        XCTAssertNotNil(badge?.unlockedAt)
        XCTAssertEqual(badge?.currentValue ?? -1, 0, accuracy: 0.1)
    }
}
