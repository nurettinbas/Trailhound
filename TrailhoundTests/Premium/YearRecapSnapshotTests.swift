import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class YearRecapSnapshotTests: XCTestCase {
    func testYearBoundaryExcludesAdjacentYear() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let inYear = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 8))!
        let previousYear = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 23))!
        let nextYear = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 1))!
        for date in [inYear, previousYear, nextYear] {
            let trip = Trip(
                startedAt: date,
                endedAt: date.addingTimeInterval(1800),
                distanceMeters: 10_000,
                estimatedFuelCost: 40,
                startLocality: date == inYear ? "Istanbul" : "Ankara"
            )
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: 2026, storeVersion: 1, now: inYear)
        XCTAssertEqual(snapshot.tripCount, 1)
        XCTAssertEqual(snapshot.distanceMeters, 10_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.cityCount, 1)
        XCTAssertEqual(snapshot.topCities, ["Istanbul"])
    }

    func testSkipsCityPageWhenEveryLocalityIsNil() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let trip = Trip(
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now,
            distanceMeters: 8_000
        )
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: year, storeVersion: 1, now: now)
        XCTAssertEqual(snapshot.cityCount, 0)
        XCTAssertTrue(snapshot.topCities.isEmpty)
        XCTAssertTrue(snapshot.hasData)
    }

    func testRecapMotionTokensVanishWhenReduceMotionIsOn() {
        XCTAssertNil(TrailhoundMotion.recapPage(reduceMotion: true))
        XCTAssertNil(TrailhoundMotion.recapCountUp(reduceMotion: true))
        XCTAssertNil(TrailhoundMotion.badgeUnlock(reduceMotion: true))
        XCTAssertNil(TrailhoundMotion.recapHold(reduceMotion: true))
        XCTAssertNil(TrailhoundMotion.recapSegmentFill(reduceMotion: true))
        XCTAssertNotNil(TrailhoundMotion.recapPage(reduceMotion: false))
        _ = TrailhoundMotion.recapSceneTransition(reduceMotion: true, advancing: true)
        _ = TrailhoundMotion.recapSceneTransition(reduceMotion: false, advancing: false)
        _ = TrailhoundMotion.recapCopyTransition(reduceMotion: true)
        _ = TrailhoundMotion.recapCopyTransition(reduceMotion: false)
    }

    func testHubTeaserIdleIntervalStaysCheap() {
        XCTAssertEqual(RecapHubTeaserMetrics.idleInterval, 1.0 / 8.0, accuracy: 0.0001)
        XCTAssertEqual(RecapHubTeaserMetrics.posterHeight, 148)
        XCTAssertEqual(StatsCardTokens.posterHeight, RecapHubTeaserMetrics.posterHeight)
        XCTAssertEqual(StatsCardTokens.posterOverlayInsets.top, 8)
        XCTAssertEqual(StatsCardTokens.posterOverlayInsets.leading, 10)
        XCTAssertEqual(RecapHubTeaserMetrics.emptyHeight, 72)
        XCTAssertEqual(RecapSceneMotion.phase(0, at: 12), 0)
    }

    func testJanuaryUsesPreviousCalendarYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2027, month: 1, day: 15))!
        let december = calendar.date(from: DateComponents(year: 2026, month: 12, day: 15))!
        XCTAssertEqual(RecapYearPolicy.displayYear(now: january, calendar: calendar), 2026)
        XCTAssertEqual(RecapYearPolicy.displayYear(now: december, calendar: calendar), 2026)
        XCTAssertFalse(RecapYearPolicy.shouldPresent(.empty(year: 2026)))
    }

    func testRecapNotificationPolicyIsJanuaryOnlyAndSkipsSeen() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2027, month: 1, day: 8, hour: 12))!
        let february = calendar.date(from: DateComponents(year: 2027, month: 2, day: 1, hour: 9))!
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!
        XCTAssertEqual(RecapNotificationPolicy.catchUpYear(now: january, calendar: calendar), 2026)
        XCTAssertNil(RecapNotificationPolicy.catchUpYear(now: february, calendar: calendar))
        let fire = RecapNotificationPolicy.fireDate(forRecapYear: 2026, calendar: calendar)!
        XCTAssertEqual(calendar.component(.year, from: fire), 2027)
        XCTAssertEqual(calendar.component(.month, from: fire), 1)
        XCTAssertEqual(calendar.component(.day, from: fire), 1)
        XCTAssertEqual(calendar.component(.hour, from: fire), 9)
        XCTAssertTrue(fire > september)
        XCTAssertTrue(RecapNotificationPolicy.shouldNotify(hasData: true, seen: false, alreadyNotified: false))
        XCTAssertFalse(RecapNotificationPolicy.shouldNotify(hasData: false, seen: false, alreadyNotified: false))
        XCTAssertFalse(RecapNotificationPolicy.shouldNotify(hasData: true, seen: true, alreadyNotified: false))
        XCTAssertFalse(RecapNotificationPolicy.shouldNotify(hasData: true, seen: false, alreadyNotified: true))
    }

    func testDiskCacheRejectsUnstampedPayload() throws {
        YearRecapCache.invalidate(year: 2026)
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YearRecapSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let stale = try JSONEncoder().encode(YearRecapSnapshot.empty(year: 2026))
        try stale.write(to: url.appendingPathComponent("2026.json"))
        XCTAssertNil(YearRecapCache.load(year: 2026))
        YearRecapCache.invalidate(year: 2026)
    }

    func testExpenseInvalidateRebuildsPaidTotal() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let inYear = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 8))!
        let trip = Trip(
            startedAt: inYear,
            endedAt: inYear.addingTimeInterval(1800),
            distanceMeters: 10_000,
            estimatedFuelCost: 40
        )
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()
        YearRecapCache.invalidate(year: 2026)

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let first = await loader.snapshot(year: 2026, storeVersion: 1, now: inYear)
        XCTAssertEqual(first.paidExpenses, 0, accuracy: 0.1)
        XCTAssertEqual(first.estimatedFuelCost, 40, accuracy: 0.1)

        context.insert(VehicleExpense(category: .service, amount: 250, occurredAt: inYear))
        try context.save()
        YearRecapCache.invalidate(yearContaining: inYear)
        let second = await loader.snapshot(year: 2026, storeVersion: 2, now: inYear)
        XCTAssertEqual(second.paidExpenses, 250, accuracy: 0.1)
        XCTAssertEqual(second.estimatedFuelCost, 40, accuracy: 0.1)
        XCTAssertEqual(second.estimatedFuelCost + second.paidExpenses, 290, accuracy: 0.1)
    }

    func testYearScopedRouteCountIgnoresLifetimeAggregate() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let thisYear = calendar.date(from: DateComponents(year: 2026, month: 4, day: 2, hour: 9))!
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 4, day: 2, hour: 9))!

        func makeTrip(at date: Date) -> Trip {
            let trip = Trip(
                startedAt: date,
                endedAt: date.addingTimeInterval(1200),
                distanceMeters: 9_000,
                startPlaceName: "Ev",
                endPlaceName: "Ofis"
            )
            trip.startLatitude = 41.0
            trip.startLongitude = 29.0
            trip.endLatitude = 41.1
            trip.endLongitude = 29.1
            return trip
        }

        for _ in 0..<3 {
            let trip = makeTrip(at: thisYear)
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        for _ in 0..<17 {
            let trip = makeTrip(at: lastYear)
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: 2026, storeVersion: 1, now: thisYear)
        XCTAssertEqual(snapshot.topRouteCount, 3)
        XCTAssertEqual(snapshot.topRouteStart, "Ev")
        XCTAssertEqual(snapshot.topRouteEnd, "Ofis")
        let pages = RecapStoryPagePolicy.pages(for: snapshot)
        XCTAssertTrue(pages.contains(.route))
    }

    func testCustomCategoryCountsAsOtherNotBusiness() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()
        let year = RecapYearPolicy.displayYear(now: now)
        guard let inYear = calendar.date(from: DateComponents(year: year, month: 6, day: 10, hour: 8)) else {
            return XCTFail("expected a date in recap year")
        }
        let customID = UUID().uuidString
        let trip = Trip(
            startedAt: inYear,
            endedAt: inYear.addingTimeInterval(3600),
            distanceMeters: 5_000
        )
        trip.categoryID = customID
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: year, storeVersion: 1, now: now)
        XCTAssertEqual(snapshot.businessDistanceMeters, 0, accuracy: 0.1)
        XCTAssertEqual(snapshot.otherDistanceMeters, 5_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.personalDistanceMeters, snapshot.otherDistanceMeters, accuracy: 0.1)
    }

    func testPlaybackFillsLastPageThenFinishes() {
        var playback = RecapStoryPlayback(pageCount: 3, autoplayEnabled: true)
        XCTAssertEqual(playback.advance(), .moved)
        XCTAssertEqual(playback.advance(), .moved)
        XCTAssertTrue(playback.isLastPage)
        XCTAssertFalse(playback.isPaused)
        XCTAssertEqual(playback.advance(), .finished)
        XCTAssertTrue(playback.isLastPage)

        var first = RecapStoryPlayback(pageCount: 3, autoplayEnabled: true)
        XCTAssertEqual(first.retreat(), .stay)

        var reduced = RecapStoryPlayback(pageCount: 3, autoplayEnabled: false)
        XCTAssertEqual(reduced.consume(10), .stay)
        XCTAssertEqual(reduced.pageIndex, 0)

        var timed = RecapStoryPlayback(pageCount: 3, autoplayEnabled: true)
        XCTAssertEqual(timed.consume(RecapStoryPlayback.pageDuration), .moved)
        XCTAssertEqual(timed.pageIndex, 1)
        XCTAssertEqual(timed.consume(RecapStoryPlayback.pageDuration), .moved)
        XCTAssertEqual(timed.pageIndex, 2)
        XCTAssertTrue(timed.isLastPage)
        XCTAssertFalse(timed.isPaused)
        XCTAssertEqual(timed.consume(RecapStoryPlayback.pageDuration), .finished)
        XCTAssertEqual(timed.pageIndex, 2)
        timed.pause()
        XCTAssertEqual(timed.consume(RecapStoryPlayback.pageDuration), .stay)
        XCTAssertEqual(timed.pageIndex, 2)
    }

    func testStoryTapUsesLeftThirdForBack() {
        XCTAssertEqual(RecapStoryTapMetrics.backWidthFraction, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertTrue(RecapStoryTapMetrics.isBack(x: 0, width: 390))
        XCTAssertTrue(RecapStoryTapMetrics.isBack(x: 120, width: 390))
        XCTAssertFalse(RecapStoryTapMetrics.isBack(x: 200, width: 390))
        XCTAssertFalse(RecapStoryTapMetrics.isBack(x: 389, width: 390))
        XCTAssertFalse(RecapStoryTapMetrics.isBack(x: 0, width: 0))
    }

    func testStoryChromeSitsBelowDynamicIsland() {
        XCTAssertEqual(RecapStoryChromeMetrics.topPadding(windowTop: 0), 62, accuracy: 0.001)
        XCTAssertEqual(RecapStoryChromeMetrics.topPadding(windowTop: 59), 67, accuracy: 0.001)
        XCTAssertEqual(RecapStoryChromeMetrics.topPadding(windowTop: 20), 28, accuracy: 0.001)
        XCTAssertGreaterThan(RecapStoryChromeMetrics.minimumTopInset, 50)
    }

    func testBadgeSlotsStayCenteredWithoutOverlap() {
        let size = CGSize(width: 390, height: 844)
        XCTAssertEqual(RecapStoryBadgeLayout.rowPattern(count: 5), [3, 2])
        XCTAssertEqual(RecapStoryBadgeLayout.overflowCount(8), 2)

        let slots = RecapStoryBadgeLayout.slots(in: size, count: 5)
        XCTAssertEqual(slots.count, 5)
        XCTAssertTrue(slots.allSatisfy { $0.minX >= -0.5 && $0.maxX <= size.width + 0.5 })
        XCTAssertTrue(slots.allSatisfy { $0.minY > size.height * 0.08 && $0.midY < size.height * 0.62 })

        for index in 0..<slots.count {
            for other in (index + 1)..<slots.count {
                XCTAssertFalse(
                    slots[index].insetBy(dx: 0.5, dy: 0.5).intersects(slots[other]),
                    "slot \(index) overlaps \(other)"
                )
            }
        }

        let medal = RecapStoryBadgeLayout.medalSize(in: size, count: 5)
        let medals = slots.map { RecapStoryBadgeLayout.medalRect(in: $0, medal: medal, offsetY: 5) }
        for index in 0..<medals.count {
            for other in (index + 1)..<medals.count {
                XCTAssertFalse(
                    medals[index].intersects(medals[other]),
                    "medal \(index) overlaps \(other)"
                )
            }
        }

        let firstRowMid = (slots[0].minX + slots[2].maxX) / 2
        let secondRowMid = (slots[3].midX + slots[4].midX) / 2
        XCTAssertEqual(firstRowMid, size.width / 2, accuracy: 0.5)
        XCTAssertEqual(secondRowMid, size.width / 2, accuracy: 0.5)
    }

    func testStorySessionAndPagesAreNeverEmpty() {
        let empty = YearRecapSnapshot.empty(year: 2026)
        let pages = RecapStoryPagePolicy.pages(for: empty)
        XCTAssertEqual(pages.first, .intro)
        XCTAssertTrue(pages.contains(.distance))
        XCTAssertEqual(pages.last, .closing)
        XCTAssertGreaterThanOrEqual(pages.count, 3)

        let session = RecapStorySession(snapshot: empty)
        XCTAssertEqual(session.snapshot.year, 2026)
        XCTAssertNotEqual(session.id, RecapStorySession(snapshot: empty).id)
        XCTAssertFalse(RecapYearPolicy.shouldPresent(empty))
        XCTAssertFalse(RecapYearPolicy.shouldPresent(nil))
    }

    func testBusiestMonthIsMonthNameNotYear0001() {
        let name = DateFormatters.formatMonthName(month: 8, year: 2026)
        XCTAssertFalse(name.contains("0001"))
        XCTAssertFalse(name.contains("2026"))
        XCTAssertFalse(name.isEmpty)
    }

    func testBadgePageKeepsKnownIDsAndSkipsUnknown() {
        var withBadges = YearRecapSnapshot.empty(year: 2026)
        withBadges.unlockedAchievementIDs = ["first.trip", "not.a.badge", "night.owl"]
        XCTAssertTrue(RecapStoryPagePolicy.pages(for: withBadges).contains(.badges))

        var unknownOnly = YearRecapSnapshot.empty(year: 2026)
        unknownOnly.unlockedAchievementIDs = ["not.a.badge"]
        XCTAssertFalse(RecapStoryPagePolicy.pages(for: unknownOnly).contains(.badges))
    }

    func testRecapBadgesFallBackToLifetimeWhenNoneUnlockedThisYear() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let previousUnlock = calendar.date(from: DateComponents(year: 2024, month: 3, day: 2, hour: 10))!
        let row = AchievementProgress(achievementID: AchievementID.firstTrip.rawValue, currentValue: 1)
        row.unlockedAt = previousUnlock
        context.insert(row)
        try context.save()
        YearRecapCache.invalidate(year: 2026)

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let snapshot = await loader.snapshot(year: 2026, storeVersion: 1, now: now)
        XCTAssertEqual(snapshot.unlockedAchievementIDs, [AchievementID.firstTrip.rawValue])
    }

    func testRecapBadgesPreferUnlocksFromTheRecapYear() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let thisYear = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9))!
        let previousYear = calendar.date(from: DateComponents(year: 2024, month: 3, day: 2, hour: 10))!
        let yearRow = AchievementProgress(achievementID: AchievementID.firstTrip.rawValue, currentValue: 1)
        yearRow.unlockedAt = thisYear
        let older = AchievementProgress(achievementID: AchievementID.nightOwl.rawValue, currentValue: 200_000)
        older.unlockedAt = previousYear
        context.insert(yearRow)
        context.insert(older)
        try context.save()
        YearRecapCache.invalidate(year: 2026)

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: 2026, storeVersion: 1, now: thisYear)
        XCTAssertEqual(snapshot.unlockedAchievementIDs, [AchievementID.firstTrip.rawValue])
    }

    func testRecapSceneMotionPhaseStaysInUnitInterval() {
        XCTAssertEqual(RecapSceneMotion.phase(0, at: 3), 0)
        XCTAssertEqual(RecapSceneMotion.phase(-4, at: 1), 0)
        XCTAssertEqual(RecapSceneMotion.saw(0, at: 2), 0)
        let samples: [TimeInterval] = [0, 1.5, 8, 19.2, 40]
        for time in samples {
            let sine = RecapSceneMotion.phase(8, at: time)
            XCTAssertGreaterThanOrEqual(sine, 0)
            XCTAssertLessThanOrEqual(sine, 1)
            let signed = RecapSceneMotion.signedPhase(8, at: time)
            XCTAssertGreaterThanOrEqual(signed, -1)
            XCTAssertLessThanOrEqual(signed, 1)
            let saw = RecapSceneMotion.saw(10, at: time)
            XCTAssertGreaterThanOrEqual(saw, 0)
            XCTAssertLessThanOrEqual(saw, 1)
        }
        XCTAssertEqual(RecapSceneMotion.phase(8, at: 0), RecapSceneMotion.phase(8, at: 8), accuracy: 0.0001)
        XCTAssertEqual(RecapSceneMotion.saw(10, at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(RecapSceneMotion.saw(10, at: 5), 0.5, accuracy: 0.0001)
    }

    func testShareImageRendersEachStoryPage() throws {
        var snapshot = YearRecapSnapshot.empty(year: 2026)
        snapshot.tripCount = 12
        snapshot.distanceMeters = 50_000
        snapshot.duration = 3_600
        snapshot.cityCount = 3
        snapshot.topCities = ["Istanbul"]
        snapshot.topRouteStart = "Home"
        snapshot.topRouteEnd = "Work"
        snapshot.topRouteCount = 4
        snapshot.nightDistanceMeters = 4_000
        snapshot.longestStreak = 4
        snapshot.busiestMonth = 8
        snapshot.busiestMonthDistanceMeters = 8_000
        snapshot.businessDistanceMeters = 10_000
        snapshot.personalDistanceMeters = 5_000
        snapshot.estimatedFuelCost = 400
        snapshot.paidExpenses = 200
        snapshot.unlockedAchievementIDs = [AchievementID.firstTrip.rawValue]

        let pages = RecapStoryPagePolicy.pages(for: snapshot)
        XCTAssertGreaterThanOrEqual(pages.count, RecapStoryPage.allCases.count - 1)

        var pngs: [Data] = []
        for page in pages {
            let image = RecapShareRenderer.image(
                for: snapshot,
                page: page,
                palette: .gold,
                scheme: .light
            )
            XCTAssertEqual(
                image.size.width * image.scale,
                RecapShareRenderer.pixelSize.width,
                accuracy: 2
            )
            XCTAssertEqual(
                image.size.height * image.scale,
                RecapShareRenderer.pixelSize.height,
                accuracy: 2
            )
            let data = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(data.count, 4_000)
            pngs.append(data)
        }
        for index in 0..<pngs.count {
            for other in (index + 1)..<pngs.count {
                XCTAssertNotEqual(
                    pngs[index],
                    pngs[other],
                    "share PNG for \(pages[index]) matched \(pages[other])"
                )
            }
        }

        let caption = RecapShareRenderer.caption(for: snapshot)
        XCTAssertTrue(caption.contains("2026"))
        XCTAssertTrue(caption.contains("Home"))
    }
}

@MainActor
final class PremiumWidgetBridgeTests: XCTestCase {
    func testPayloadSurvivesMissingAppGroupKeys() {
        let suite = "trailhound.tests.widget.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let payload = PremiumWidgetPayload.load(from: defaults)
        XCTAssertEqual(payload.projectedTotal, 0, accuracy: 0.1)
        XCTAssertTrue(payload.showRoutePreview)
        XCTAssertNil(payload.lastTripID)
    }
}
