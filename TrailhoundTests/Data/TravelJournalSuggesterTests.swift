import CoreLocation
import XCTest
@testable import Trailhound

final class TravelJournalMapBudgetTests: XCTestCase {
    func testTwelveTripsStayAtOrBelowCap() {
        let counts = Array(repeating: 1500, count: 12)
        let allocated = TravelJournalMapBudget.allocate(pointCounts: counts, totalCap: 4000)
        XCTAssertEqual(allocated.count, 12)
        XCTAssertLessThanOrEqual(allocated.reduce(0, +), 4000)
        XCTAssertTrue(allocated.allSatisfy { $0 >= 2 })
    }

    func testDownsampleKeepsEndpoints() {
        let path = (0..<20).map {
            CLLocationCoordinate2D(latitude: Double($0), longitude: Double($0))
        }
        let sampled = TravelJournalMapBudget.downsample(path, to: 5)
        XCTAssertEqual(sampled.count, 5)
        XCTAssertEqual(sampled.first?.latitude, 0)
        XCTAssertEqual(sampled.last?.latitude, 19)
    }

    func testShortPathUnchangedWhenUnderCap() {
        XCTAssertEqual(TravelJournalMapBudget.allocate(pointCounts: [10, 20, 5], totalCap: 4000), [10, 20, 5])
    }
}

final class TravelJournalSuggesterTests: XCTestCase {
    private let home = TravelJournalHomeSnapshot(latitude: 41.0, longitude: 29.0, radiusMeters: 300)
    private let calendar = Calendar(identifier: .gregorian)

    func testWeekdayCommuteIsNotATravel() {
        let monday = date(2026, 3, 2, 8)
        let trips = [
            trip("a", start: monday, hours: 1, fromHome: true, toHome: false),
            trip("b", start: monday.addingTimeInterval(9 * 3600), hours: 1, fromHome: false, toHome: true)
        ]
        XCTAssertNil(TravelJournalSuggester.suggest(trips: trips, homes: [home], calendar: calendar))
    }

    func testAwayWeekendWithTwoNightsSuggests() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("fri", start: friday, hours: 3, fromHome: false, toHome: false, distance: 80_000),
            trip("sat", start: friday.addingTimeInterval(24 * 3600), hours: 2, fromHome: false, toHome: false, distance: 40_000),
            trip("sun", start: friday.addingTimeInterval(48 * 3600), hours: 2, fromHome: false, toHome: false, distance: 40_000)
        ]
        let suggestion = TravelJournalSuggester.suggest(trips: trips, homes: [home], calendar: calendar)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.tripIDs.count, 3)
    }

    func testNoHomePlaceYieldsNoSuggestion() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("fri", start: friday, hours: 3, fromHome: false, toHome: false, distance: 200_000)
        ]
        XCTAssertNil(TravelJournalSuggester.suggest(trips: trips, homes: [], calendar: calendar))
    }

    func testDismissedFingerprintIsSkipped() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("fri", start: friday, hours: 3, fromHome: false, toHome: false, distance: 80_000),
            trip("sat", start: friday.addingTimeInterval(24 * 3600), hours: 2, fromHome: false, toHome: false, distance: 40_000),
            trip("sun", start: friday.addingTimeInterval(48 * 3600), hours: 2, fromHome: false, toHome: false, distance: 40_000)
        ]
        let first = TravelJournalSuggester.suggest(trips: trips, homes: [home], calendar: calendar)
        XCTAssertNotNil(first)
        let skipped = TravelJournalSuggester.suggest(
            trips: trips,
            homes: [home],
            dismissedFingerprints: [first!.fingerprint],
            calendar: calendar
        )
        XCTAssertNil(skipped)
    }

    func testLongDistanceAwayDaySuggestsWithoutTwoNights() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("km", start: friday, hours: 4, fromHome: false, toHome: false, distance: 150_000)
        ]
        let suggestion = TravelJournalSuggester.suggest(trips: trips, homes: [home], calendar: calendar)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.tripIDs.count, 1)
    }

    func testInProgressTripIsIgnored() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("km", start: friday, hours: 4, fromHome: false, toHome: false, distance: 150_000, isInProgress: true)
        ]
        XCTAssertNil(TravelJournalSuggester.suggest(trips: trips, homes: [home], calendar: calendar))
    }

    func testWorkOnlyPlaceYieldsNoSuggestion() {
        let friday = date(2026, 3, 6, 18)
        let trips = [
            trip("km", start: friday, hours: 4, fromHome: false, toHome: false, distance: 200_000)
        ]
        let work = SavedPlace(name: "Office", latitude: 41.0, longitude: 29.0, kind: .work)
        let homes = TravelJournalSuggester.homeSnapshots(from: [work])
        XCTAssertTrue(homes.isEmpty)
        XCTAssertNil(TravelJournalSuggester.suggest(trips: trips, homes: homes, calendar: calendar))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func trip(
        _ id: String,
        start: Date,
        hours: Double,
        fromHome: Bool,
        toHome: Bool,
        distance: Double = 10_000,
        isInProgress: Bool = false
    ) -> TravelJournalTripSnapshot {
        let startLat = fromHome ? 41.0 : 40.0
        let endLat = toHome ? 41.0 : 40.0
        return TravelJournalTripSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(id.padding(toLength: 12, withPad: "0", startingAt: 0))") ?? UUID(),
            startedAt: start,
            endedAt: isInProgress ? nil : start.addingTimeInterval(hours * 3600),
            distanceMeters: distance,
            startLatitude: startLat,
            startLongitude: 29.0,
            endLatitude: endLat,
            endLongitude: 29.0,
            startPlaceName: fromHome ? "Home" : "Away",
            endPlaceName: toHome ? "Home" : "Away",
            journalID: nil
        )
    }
}
