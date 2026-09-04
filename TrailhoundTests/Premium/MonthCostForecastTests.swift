import SwiftData
import XCTest
@testable import Trailhound

final class MonthCostForecastTests: XCTestCase {
    func testMidMonthProjectionIncludesRemainingDaysAndInstallments() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 12))!
        var mtd: [Date: Double] = [:]
        for day in 1...15 {
            let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: day))!
            mtd[date] = 100
        }
        let expenses = [
            ForecastExpense(amount: 200, category: .casco, isInstallment: true, occurredAt: monthStart),
            ForecastExpense(amount: 50, category: .fuel, isInstallment: false, occurredAt: monthStart),
            ForecastExpense(amount: 80, category: .service, isInstallment: false, occurredAt: monthStart)
        ]
        let forecast = MonthCostForecastMath.forecast(
            now: now,
            calendar: calendar,
            mtdTripFuelByDay: mtd,
            previousMonthTripFuelByDay: [:],
            thisMonthExpenses: expenses,
            previousMonthExpenses: []
        )
        XCTAssertEqual(forecast.mtdFuel, 1_500, accuracy: 0.1)
        XCTAssertEqual(forecast.dailyRunRate, 100, accuracy: 0.1)
        XCTAssertEqual(forecast.projectedFuel, 1_500 + 14 * 100, accuracy: 0.1)
        XCTAssertEqual(forecast.installmentsDue, 200, accuracy: 0.1)
        XCTAssertEqual(forecast.loggedFuel, 50, accuracy: 0.1)
        XCTAssertEqual(forecast.otherExpenses, 80, accuracy: 0.1)
        XCTAssertEqual(forecast.projectedTotal, forecast.projectedFuel + 200 + 80, accuracy: 0.1)
        XCTAssertEqual(forecast.confidence, .high)
    }

    func testEarlyMonthUsesPreviousMonthFallback() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: 9))!
        let previous: [Date: Double] = [
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!: 300,
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 2))!: 300
        ]
        let forecast = MonthCostForecastMath.forecast(
            now: now,
            calendar: calendar,
            mtdTripFuelByDay: [calendar.startOfDay(for: now): 10],
            previousMonthTripFuelByDay: previous,
            thisMonthExpenses: [],
            previousMonthExpenses: []
        )
        XCTAssertEqual(forecast.dailyRunRate, 300, accuracy: 0.1)
        XCTAssertEqual(forecast.confidence, .low)
    }
}

@MainActor
final class MonthCostForecastStoreTests: XCTestCase {
    func testIgnoresOtherVehicleWhenFiltered() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let carA = VehicleProfile(name: "A")
        let carB = VehicleProfile(name: "B")
        context.insert(carA)
        context.insert(carB)
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        context.insert(VehicleExpense(category: .service, amount: 400, occurredAt: monthStart.addingTimeInterval(3600), vehicle: carA))
        context.insert(VehicleExpense(category: .service, amount: 900, occurredAt: monthStart.addingTimeInterval(7200), vehicle: carB))
        try context.save()

        let filtered = MonthCostForecastStore.forecast(in: context, vehicleID: carA.id, now: monthStart.addingTimeInterval(86400 * 10))
        XCTAssertEqual(filtered.otherExpenses, 400, accuracy: 0.1)
        let all = MonthCostForecastStore.forecast(in: context, vehicleID: nil, now: monthStart.addingTimeInterval(86400 * 10))
        XCTAssertEqual(all.otherExpenses, 1_300, accuracy: 0.1)
    }

    func testEVTripFuelCountsTowardDriveEstimateNotLoggedPump() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let ev = VehicleProfile(name: "EV")
        ev.fuelType = .electric
        context.insert(ev)
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let trip = Trip(
            startedAt: monthStart.addingTimeInterval(3600),
            endedAt: monthStart.addingTimeInterval(7200),
            distanceMeters: 40_000,
            estimatedFuelCost: 85,
            vehicleID: ev.id
        )
        trip.vehicle = ev
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        context.insert(VehicleExpense(category: .fuel, amount: 40, occurredAt: monthStart.addingTimeInterval(10_000), vehicle: ev))
        try context.save()

        let forecast = MonthCostForecastStore.forecast(in: context, vehicleID: ev.id, now: monthStart.addingTimeInterval(86400 * 10))
        XCTAssertEqual(forecast.mtdFuel, 85, accuracy: 0.1)
        XCTAssertEqual(forecast.loggedFuel, 40, accuracy: 0.1)
        XCTAssertEqual(forecast.otherExpenses, 0, accuracy: 0.1)
        XCTAssertEqual(forecast.projectedTotal, forecast.projectedFuel, accuracy: 0.1)
        XCTAssertNotEqual(forecast.projectedTotal, forecast.mtdFuel + forecast.loggedFuel, accuracy: 0.1)
    }
}
