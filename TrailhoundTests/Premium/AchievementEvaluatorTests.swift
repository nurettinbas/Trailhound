import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class AchievementEvaluatorTests: XCTestCase {
    override func setUp() {
        AppNotificationArchive.save([])
        AppNotificationStore.shared.reload()
        AppNotificationStore.shared.clearAll()
    }
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

    func testUnlockQueueMergesNewPendingWithoutResettingCurrent() {
        let first = AchievementDisplay(
            id: .nightOwl,
            currentValue: 5_000,
            unlockedAt: Date(),
            needsCelebration: true
        )
        let second = AchievementDisplay(
            id: .firstTrip,
            currentValue: 1,
            unlockedAt: Date(),
            needsCelebration: true
        )
        let merged = AchievementUnlockQueue.merging(queued: [first], pending: [first, second])
        XCTAssertEqual(merged.map(\.id), [.nightOwl, .firstTrip])
    }

    func testUnlockQueueEmptyTakesPending() {
        let pending = [
            AchievementDisplay(
                id: .streak7,
                currentValue: 7,
                unlockedAt: Date(),
                needsCelebration: true
            )
        ]
        XCTAssertEqual(AchievementUnlockQueue.merging(queued: [], pending: pending).map(\.id), [.streak7])
    }

    func testDistance100000SeedsFromExistingMetersWithoutCelebration() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let row = AchievementProgress(achievementID: AchievementID.distance10000.rawValue, currentValue: 120_000_000)
        row.unlockedAt = Date().addingTimeInterval(-86_400)
        context.insert(row)
        try context.save()
        let badge = AchievementEvaluator.displays(in: context).first { $0.id == .distance100000 }
        XCTAssertEqual(badge?.currentValue ?? 0, 120_000_000, accuracy: 1)
        XCTAssertNotNil(badge?.unlockedAt)
        XCTAssertFalse(badge?.needsCelebration ?? true)
    }

    func testDistance100000SeedsProgressWithoutUnlockingEarly() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let row = AchievementProgress(achievementID: AchievementID.distance10000.rawValue, currentValue: 50_000_000)
        row.unlockedAt = Date().addingTimeInterval(-86_400)
        context.insert(row)
        try context.save()
        let badge = AchievementEvaluator.displays(in: context).first { $0.id == .distance100000 }
        XCTAssertEqual(badge?.currentValue ?? 0, 50_000_000, accuracy: 1)
        XCTAssertNil(badge?.unlockedAt)
    }

    func testDistanceLadderListsBeforePredecessorUnlocks() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let ids = Set(AchievementEvaluator.displays(in: context).map(\.id))
        XCTAssertEqual(
            ids.intersection([.distance100, .distance1000, .distance10000, .distance100000]),
            [.distance100, .distance1000, .distance10000, .distance100000]
        )
        XCTAssertFalse(ids.contains(.business50))
        XCTAssertFalse(ids.contains(.streak30))
        XCTAssertFalse(ids.contains(.cities25))
    }

    func testStripPreviewOmitsLockedMedals() {
        let unlocked = AchievementDisplay(
            id: .firstTrip,
            currentValue: 1,
            unlockedAt: Date(),
            needsCelebration: false
        )
        let locked = AchievementDisplay(
            id: .distance100,
            currentValue: 40_000,
            unlockedAt: nil,
            needsCelebration: false
        )
        XCTAssertEqual(AchievementStripPreview.medals(from: [unlocked, locked]).map(\.id), [.firstTrip])
        XCTAssertTrue(AchievementStripPreview.medals(from: [locked]).isEmpty)
    }

    func testApplyReturnsNewlyUnlockedWithoutInboxWhenNotifyFalse() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 120_000
        )
        context.insert(trip)
        let newly = AchievementEvaluator.apply(
            trip: trip,
            sign: 1,
            localities: [],
            in: context,
            notify: false
        )
        XCTAssertTrue(newly.contains(.firstTrip))
        XCTAssertTrue(newly.contains(.distance100))
        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)
        let displays = AchievementEvaluator.displays(in: context)
        XCTAssertFalse(displays.first { $0.id == .firstTrip }?.needsCelebration ?? true)
        XCTAssertFalse(displays.first { $0.id == .distance100 }?.needsCelebration ?? true)
    }

    func testLiveApplyLeavesCelebrationPendingWithoutInboxInUnitTests() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 120_000
        )
        context.insert(trip)
        let newly = AchievementEvaluator.apply(
            trip: trip,
            sign: 1,
            localities: [],
            in: context,
            notify: true
        )
        XCTAssertTrue(newly.contains(.firstTrip))
        XCTAssertTrue(newly.contains(.distance100))
        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)
        let displays = AchievementEvaluator.displays(in: context)
        XCTAssertTrue(displays.first { $0.id == .firstTrip }?.needsCelebration ?? false)
        XCTAssertTrue(displays.first { $0.id == .distance100 }?.needsCelebration ?? false)
    }

    func testNotifyAchievementsUnlockedRecordsOneInboxRowPerBadge() {
        TripNotificationService.notifyAchievementsUnlocked([.firstTrip, .nightOwl])
        let items = AppNotificationStore.shared.items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { AppNotificationStore.shared.kind(for: $0) == .achievementUnlocked })
        XCTAssertEqual(Set(items.compactMap(\.target)), ["first.trip", "night.owl"])
        XCTAssertEqual(items.first?.action, TripNotificationService.openAchievementsAction)
    }

    func testRebuildDoesNotRecordAchievementNotifications() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 120_000
        )
        context.insert(trip)
        AchievementEvaluator.rebuild(in: context)
        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)
        XCTAssertNotNil(AchievementEvaluator.displays(in: context).first { $0.id == .firstTrip }?.unlockedAt)
        XCTAssertFalse(AchievementEvaluator.displays(in: context).first { $0.id == .firstTrip }?.needsCelebration ?? true)
    }

    func testRebuildUnlocksHistoricalTripsWithoutCelebrationOrInbox() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let firstEnded = Date().addingTimeInterval(-86_400 * 40)
        let laterEnded = Date().addingTimeInterval(-86_400 * 10)
        let first = Trip(
            startedAt: firstEnded.addingTimeInterval(-1_800),
            endedAt: firstEnded,
            distanceMeters: 8_000
        )
        let later = Trip(
            startedAt: laterEnded.addingTimeInterval(-3_600),
            endedAt: laterEnded,
            distanceMeters: 110_000
        )
        context.insert(first)
        context.insert(later)
        try context.save()

        AchievementEvaluator.rebuild(in: context)

        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)
        let displays = AchievementEvaluator.displays(in: context)
        let firstTrip = displays.first { $0.id == .firstTrip }
        let distance = displays.first { $0.id == .distance100 }
        XCTAssertEqual(firstTrip?.unlockedAt, firstEnded)
        XCTAssertEqual(distance?.unlockedAt, laterEnded)
        XCTAssertEqual(distance?.currentValue ?? 0, 118_000, accuracy: 1)
        XCTAssertFalse(firstTrip?.needsCelebration ?? true)
        XCTAssertFalse(distance?.needsCelebration ?? true)
        XCTAssertTrue(firstTrip?.isUnlocked ?? false)
        XCTAssertTrue(distance?.isUnlocked ?? false)
    }

    func testMaintenanceAchievementReplayBackfillsExistingTripsSilently() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let ended = Date().addingTimeInterval(-86_400 * 20)
        let trip = Trip(
            startedAt: ended.addingTimeInterval(-2_000),
            endedAt: ended,
            distanceMeters: 250_000
        )
        context.insert(trip)
        try context.save()

        await PremiumDerivedMaintenance.rebuildAchievements(container: container)

        XCTAssertTrue(AppNotificationStore.shared.items.isEmpty)
        let displays = AchievementEvaluator.displays(in: context)
        XCTAssertEqual(displays.first { $0.id == .firstTrip }?.unlockedAt, ended)
        XCTAssertEqual(displays.first { $0.id == .distance100 }?.unlockedAt, ended)
        XCTAssertFalse(displays.first { $0.id == .firstTrip }?.needsCelebration ?? true)
        XCTAssertFalse(displays.first { $0.id == .distance100 }?.needsCelebration ?? true)
    }
}
