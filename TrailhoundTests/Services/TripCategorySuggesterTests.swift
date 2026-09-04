import CoreLocation
import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class TripCategorySuggesterTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private let homeCoordinate = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
    private let workCoordinate = CLLocationCoordinate2D(latitude: 41.1, longitude: 29.1)

    func testFrequentRouteMajoritySuggestsLearnedCategory() {
        let history = (0..<3).map { index in
            makeTrip(
                startPlace: "Ev",
                endPlace: "Ofis",
                category: .business,
                startedAt: weekday(hour: 10).addingTimeInterval(TimeInterval(index * 86_400))
            )
        }
        let candidate = makeTrip(startPlace: "Ev", endPlace: "Ofis", startedAt: weekday(hour: 10))
        let histogram = FrequentRoutesService.categoryHistogram(from: history)

        let suggestion = TripCategorySuggester.suggestion(
            for: candidate,
            places: [],
            histogram: histogram,
            calendar: calendar
        )

        XCTAssertEqual(suggestion?.categoryID, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(suggestion?.reason, .route)
        XCTAssertEqual(suggestion?.confidence, 1, accuracy: 0.001)
    }

    func testDefaultPersonalTripsDoNotTeachTheHistogram() {
        let personal = (0..<4).map { _ in
            makeTrip(startPlace: "Ev", endPlace: "Ofis", category: .personal, startedAt: weekday(hour: 10))
        }
        let histogram = FrequentRoutesService.categoryHistogram(from: personal)
        XCTAssertTrue(histogram.isEmpty)

        let candidate = makeTrip(startPlace: "Ev", endPlace: "Ofis", startedAt: saturday(hour: 10))
        let suggestion = TripCategorySuggester.suggestion(
            for: candidate,
            places: [],
            histogram: histogram,
            calendar: calendar
        )
        XCTAssertNil(suggestion)
    }

    func testHomeToWorkPlaceKindSuggestsBusinessWithoutHistory() {
        let candidate = makeCommuteTrip(startedAt: saturday(hour: 10))
        let suggestion = TripCategorySuggester.suggestion(
            for: candidate,
            places: commutePlaces(),
            histogram: [:],
            calendar: calendar
        )

        XCTAssertEqual(suggestion?.categoryID, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(suggestion?.reason, .place)
    }

    func testWeekdayWorkHoursSuggestBusiness() {
        let candidate = makeTrip(startedAt: weekday(hour: 10))
        let suggestion = TripCategorySuggester.suggestion(
            for: candidate,
            places: [],
            histogram: [:],
            calendar: calendar
        )

        XCTAssertEqual(suggestion?.categoryID, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(suggestion?.reason, .hours)
    }

    func testWeekendHoursDoNotSuggest() {
        let candidate = makeTrip(startedAt: saturday(hour: 10))
        let suggestion = TripCategorySuggester.suggestion(
            for: candidate,
            places: [],
            histogram: [:],
            calendar: calendar
        )
        XCTAssertNil(suggestion)
    }

    func testOutsideWorkHoursDoesNotSuggest() {
        let candidate = makeTrip(startedAt: weekday(hour: 20))
        let suggestion = TripCategorySuggester.suggestion(
            for: candidate,
            places: [],
            histogram: [:],
            calendar: calendar
        )
        XCTAssertNil(suggestion)
    }

    func testUserOriginBlocksSuggestion() {
        let candidate = makeCommuteTrip(startedAt: weekday(hour: 10))
        candidate.categoryOrigin = .user
        let suggestion = TripCategorySuggester.suggestion(
            for: candidate,
            places: commutePlaces(),
            histogram: [:],
            calendar: calendar
        )
        XCTAssertNil(suggestion)
    }

    func testDismissedOriginBlocksSuggestion() {
        let candidate = makeCommuteTrip(startedAt: weekday(hour: 10))
        candidate.categoryOrigin = .dismissed
        let suggestion = TripCategorySuggester.suggestion(
            for: candidate,
            places: commutePlaces(),
            histogram: [:],
            calendar: calendar
        )
        XCTAssertNil(suggestion)
    }

    func testDoesNotSuggestCurrentCategory() {
        let candidate = makeCommuteTrip(startedAt: weekday(hour: 10), category: .business)
        candidate.categoryOriginRaw = TripCategoryOrigin.default.rawValue
        let suggestion = TripCategorySuggester.suggestion(
            for: candidate,
            places: commutePlaces(),
            histogram: [:],
            calendar: calendar
        )
        XCTAssertNil(suggestion)
    }

    func testRouteBeatsPlaceAndHours() {
        let customID = UUID().uuidString
        let history = (0..<3).map { _ in
            let trip = makeCommuteTrip(startedAt: weekday(hour: 10), category: .personal)
            trip.categoryID = customID
            trip.categoryOrigin = .user
            return trip
        }
        let candidate = makeCommuteTrip(startedAt: weekday(hour: 10))
        let histogram = FrequentRoutesService.categoryHistogram(from: history)

        let suggestion = TripCategorySuggester.suggestion(
            for: candidate,
            places: commutePlaces(),
            histogram: histogram,
            calendar: calendar
        )

        XCTAssertEqual(suggestion?.categoryID, customID)
        XCTAssertEqual(suggestion?.reason, .route)
    }

    func testRefreshPendingWritesSuggestion() {
        let trip = makeCommuteTrip(startedAt: saturday(hour: 11))
        TripCategorySuggestionService.refreshPending(
            on: trip,
            among: [trip],
            places: commutePlaces(),
            enabled: true,
            calendar: calendar
        )
        XCTAssertEqual(trip.pendingSuggestedCategoryID, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(trip.pendingSuggestionReason, .place)
    }

    func testRefreshPendingClearsWhenDisabled() {
        let trip = makeCommuteTrip(startedAt: saturday(hour: 11))
        trip.pendingSuggestedCategoryID = BuiltInCategory.businessID.uuidString
        trip.pendingSuggestionReasonRaw = TripCategorySuggestionReason.place.rawValue
        TripCategorySuggestionService.refreshPending(
            on: trip,
            among: [trip],
            places: commutePlaces(),
            enabled: false,
            calendar: calendar
        )
        XCTAssertNil(trip.pendingSuggestedCategoryID)
        XCTAssertNil(trip.pendingSuggestionReasonRaw)
    }

    func testAcceptPendingUpdatesRollupCategory() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = makeCommuteTrip(startedAt: weekday(hour: 10), category: .personal)
        trip.distanceMeters = 5_000
        context.insert(trip)
        try context.save()
        TripRollupService.add(trip, in: context)

        trip.pendingSuggestedCategoryID = BuiltInCategory.businessID.uuidString
        trip.pendingSuggestionReasonRaw = TripCategorySuggestionReason.place.rawValue
        TripCategorySuggestionService.acceptPending(trip, in: context)
        try context.save()

        XCTAssertEqual(trip.categoryID, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(trip.categoryOrigin, .accepted)
        XCTAssertNil(trip.pendingSuggestedCategoryID)

        let rollups = try context.fetch(FetchDescriptor<TripDailyRollup>())
        XCTAssertEqual(rollups.count, 1)
        XCTAssertEqual(rollups.first?.categoryID, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(rollups.first?.tripCount, 1)
    }

    func testApplyUserCategoryClearsPendingAndSetsOrigin() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = makeTrip(startedAt: weekday(hour: 10), category: .personal)
        context.insert(trip)
        try context.save()
        TripRollupService.add(trip, in: context)

        trip.pendingSuggestedCategoryID = BuiltInCategory.businessID.uuidString
        TripCategorySuggestionService.applyUserCategory(
            BuiltInCategory.businessID.uuidString,
            to: trip,
            in: context
        )

        XCTAssertEqual(trip.categoryOrigin, .user)
        XCTAssertNil(trip.pendingSuggestedCategoryID)
        XCTAssertEqual(trip.categoryID, BuiltInCategory.businessID.uuidString)
    }

    func testRematchWritesPendingOnDefaultOriginTrips() {
        let trip = makeCommuteTrip(startedAt: saturday(hour: 11))
        PlaceMatchingService.rematchTrips(
            [trip],
            places: commutePlaces(),
            privacyRadius: 500,
            suggestionsEnabled: true,
            workHours: .default
        )
        XCTAssertEqual(trip.pendingSuggestedCategoryID, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(trip.pendingSuggestionReason, .place)
    }

    // MARK: - Helpers

    private func weekday(hour: Int) -> Date {
        date(year: 2026, month: 9, day: 8, hour: hour)
    }

    private func saturday(hour: Int) -> Date {
        date(year: 2026, month: 9, day: 5, hour: hour)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func commutePlaces() -> [SavedPlace] {
        [
            SavedPlace(
                name: "Ev",
                latitude: homeCoordinate.latitude,
                longitude: homeCoordinate.longitude,
                radiusMeters: 300,
                kind: .home
            ),
            SavedPlace(
                name: "İş",
                latitude: workCoordinate.latitude,
                longitude: workCoordinate.longitude,
                radiusMeters: 300,
                kind: .work
            )
        ]
    }

    private func makeCommuteTrip(
        startedAt: Date,
        category: TripCategory = .personal
    ) -> Trip {
        let trip = makeTrip(
            startPlace: "Ev",
            endPlace: "İş",
            category: category,
            startedAt: startedAt
        )
        trip.startLatitude = homeCoordinate.latitude
        trip.startLongitude = homeCoordinate.longitude
        trip.endLatitude = workCoordinate.latitude
        trip.endLongitude = workCoordinate.longitude
        return trip
    }

    private func makeTrip(
        startPlace: String? = nil,
        endPlace: String? = nil,
        category: TripCategory = .personal,
        startedAt: Date
    ) -> Trip {
        Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            distanceMeters: 8_000,
            category: category,
            startPlaceName: startPlace,
            endPlaceName: endPlace
        )
    }
}
