import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class VehicleCareMigrationTests: XCTestCase {
    func testV13SupportsSchedulesAndExpenses() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: TrailhoundSchemaV13.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Test Car", consumption: 7.0)
        context.insert(vehicle)

        let schedule = VehicleSchedule(
            kind: .service,
            nextDueDate: Date().addingTimeInterval(86400 * 14),
            intervalKind: .everyMonths,
            intervalMonths: 12,
            vehicle: vehicle
        )
        context.insert(schedule)

        let expense = VehicleExpense(
            category: .fuel,
            amount: 500,
            vehicle: vehicle
        )
        context.insert(expense)
        try context.save()

        let trips = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(trips.count, 0)

        let schedules = try context.fetch(FetchDescriptor<VehicleSchedule>())
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedules.first?.kind, .service)

        let expenses = try context.fetch(FetchDescriptor<VehicleExpense>())
        XCTAssertEqual(expenses.count, 1)
        XCTAssertEqual(expenses.first?.amount, 500)
    }

    func testInMemoryFactoryIncludesCareModels() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Factory Car")
        context.insert(vehicle)
        let schedule = VehicleSchedule(kind: .casco, nextDueDate: Date(), vehicle: vehicle)
        context.insert(schedule)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<VehicleSchedule>()).count, 1)
        XCTAssertEqual(ModelContainerFactory.currentSchemaVersion, 18)
    }

    func testTripDataSurvivesAlongsideCareModels() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Keeper")
        context.insert(vehicle)
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 12_500,
            vehicleID: vehicle.id,
            vehicle: vehicle
        )
        context.insert(trip)
        try context.save()

        context.insert(VehicleExpense(category: .service, amount: 2500, vehicle: vehicle))
        try context.save()

        let trips = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.distanceMeters, 12_500)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VehicleExpense>()).count, 1)
    }

    func testV14KeepsExistingExpensesAsOneShot() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: TrailhoundSchemaV14.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Legacy Expense")
        context.insert(vehicle)
        context.insert(VehicleExpense(category: .fuel, amount: 90, vehicle: vehicle))
        try context.save()

        let expense = try XCTUnwrap(context.fetch(FetchDescriptor<VehicleExpense>()).first)
        XCTAssertNil(expense.installmentGroupID)
        XCTAssertNil(expense.installmentIndex)
        XCTAssertNil(expense.installmentCount)
        XCTAssertNil(expense.installmentTotalAmount)
        XCTAssertFalse(expense.isInstallment)
        XCTAssertEqual(expense.amount, 90)
    }
}
