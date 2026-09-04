import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class TravelJournalMembershipTests: XCTestCase {
    func testAssigningMovesTripBetweenJournals() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 12_000,
            estimatedFuelCost: 40,
            dynamicFuelCost: 42
        )
        context.insert(trip)
        let alpha = TravelJournal(title: "Alpha")
        let beta = TravelJournal(title: "Beta")
        context.insert(alpha)
        context.insert(beta)

        TravelJournalTotals.assign(trip: trip, to: alpha, in: context)
        XCTAssertEqual(trip.journalID, alpha.id)
        XCTAssertEqual(alpha.tripCount, 1)
        XCTAssertEqual(alpha.fuelCost, 42, accuracy: 0.01)

        TravelJournalTotals.assign(trip: trip, to: beta, in: context)
        XCTAssertEqual(trip.journalID, beta.id)
        XCTAssertEqual(alpha.tripCount, 0)
        XCTAssertEqual(beta.tripCount, 1)
        XCTAssertTrue(alpha.trips.isEmpty)
    }

    func testTotalsUseDynamicFuelThenEstimated() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let withDynamic = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 5_000,
            estimatedFuelCost: 10,
            dynamicFuelCost: 15
        )
        let estimatedOnly = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 5_000,
            estimatedFuelCost: 12
        )
        context.insert(withDynamic)
        context.insert(estimatedOnly)
        let journal = TravelJournal(title: "Costs")
        context.insert(journal)
        TravelJournalTotals.assign(trip: withDynamic, to: journal, in: context)
        TravelJournalTotals.assign(trip: estimatedOnly, to: journal, in: context)
        XCTAssertEqual(journal.fuelCost, 27, accuracy: 0.01)
        XCTAssertEqual(journal.distanceMeters, 10_000, accuracy: 0.01)
    }

    func testSameJournalMergeKeepsMembership() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let start = Date().addingTimeInterval(-7_200)
        let first = Trip(startedAt: start, endedAt: start.addingTimeInterval(1_800), distanceMeters: 3_000)
        let second = Trip(
            startedAt: start.addingTimeInterval(2_400),
            endedAt: start.addingTimeInterval(4_200),
            distanceMeters: 3_000
        )
        context.insert(first)
        context.insert(second)
        let journal = TravelJournal(title: "Merge")
        context.insert(journal)
        TravelJournalTotals.assign(trip: first, to: journal, in: context)
        TravelJournalTotals.assign(trip: second, to: journal, in: context)

        let merged = try TripMergeService.merge(trips: [first, second], into: context)
        XCTAssertEqual(merged.journalID, journal.id)
        TravelJournalTotals.refresh(journal)
        XCTAssertEqual(journal.tripCount, 1)
    }

    func testMixedJournalMergeClearsMembership() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let start = Date().addingTimeInterval(-7_200)
        let first = Trip(startedAt: start, endedAt: start.addingTimeInterval(1_800), distanceMeters: 3_000)
        let second = Trip(
            startedAt: start.addingTimeInterval(2_400),
            endedAt: start.addingTimeInterval(4_200),
            distanceMeters: 3_000
        )
        context.insert(first)
        context.insert(second)
        let alpha = TravelJournal(title: "A")
        let beta = TravelJournal(title: "B")
        context.insert(alpha)
        context.insert(beta)
        TravelJournalTotals.assign(trip: first, to: alpha, in: context)
        TravelJournalTotals.assign(trip: second, to: beta, in: context)

        let merged = try TripMergeService.merge(trips: [first, second], into: context)
        XCTAssertNil(merged.journalID)
    }

    func testSchemaV19OpensTravelJournal() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: TrailhoundSchemaV19.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let journal = TravelJournal(title: "Opened")
        container.mainContext.insert(journal)
        try container.mainContext.save()
        let fetched = try container.mainContext.fetch(FetchDescriptor<TravelJournal>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Opened")
    }
}
