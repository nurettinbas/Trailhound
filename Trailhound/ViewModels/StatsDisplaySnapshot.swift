import Foundation
import SwiftData

struct StatsDisplaySnapshot {
    let stats: TripStats
    let previousStats: TripStats
    let dailyDistance: [DailyDistance]
    let dailyDuration: [DailyDuration]
    let dailyAverageSpeed: [DailyAverageSpeed]
    let dailyMaxSpeed: [DailyMaxSpeed]
    let categoryDistance: [CategoryDistance]
    let categoryDuration: [CategoryDuration]
    let vehicleDistance: [VehicleDistance]
    let vehicleDuration: [VehicleDuration]
    let showsVehicleBreakdownCharts: Bool

    var hasAnyDailyChart: Bool {
        !dailyDistance.isEmpty || !dailyDuration.isEmpty
            || !dailyAverageSpeed.isEmpty || !dailyMaxSpeed.isEmpty
    }

    var hasCategoryCharts: Bool {
        !categoryDistance.isEmpty || !categoryDuration.isEmpty
    }

    static let empty = StatsDisplaySnapshot(
        stats: TripStats(
            tripCount: 0,
            totalDistanceMeters: 0,
            totalDuration: 0,
            averageDuration: 0,
            estimatedFuelCost: 0
        ),
        previousStats: TripStats(
            tripCount: 0,
            totalDistanceMeters: 0,
            totalDuration: 0,
            averageDuration: 0,
            estimatedFuelCost: 0
        ),
        dailyDistance: [],
        dailyDuration: [],
        dailyAverageSpeed: [],
        dailyMaxSpeed: [],
        categoryDistance: [],
        categoryDuration: [],
        vehicleDistance: [],
        vehicleDuration: [],
        showsVehicleBreakdownCharts: false
    )

    func distanceTrendText() -> String? {
        StatsViewModel.trendText(
            current: stats.totalDistanceMeters,
            previous: previousStats.totalDistanceMeters
        )
    }

    func tripCountTrendText() -> String? {
        StatsViewModel.trendText(
            current: Double(stats.tripCount),
            previous: Double(previousStats.tripCount)
        )
    }

    func durationTrendText() -> String? {
        StatsViewModel.trendText(
            current: stats.totalDuration,
            previous: previousStats.totalDuration
        )
    }

    func averageSpeedTrendText() -> String? {
        StatsViewModel.trendText(
            current: stats.averageSpeedKmh,
            previous: previousStats.averageSpeedKmh
        )
    }

    func maxSpeedTrendText() -> String? {
        StatsViewModel.trendText(
            current: stats.maxSpeedKmh,
            previous: previousStats.maxSpeedKmh
        )
    }
}

enum StatsDisplaySnapshotBuilder {
    @MainActor
    static func build(
        completedTrips: [Trip],
        categories: [UserCategory],
        vehicles: [VehicleProfile],
        selectedPeriod: StatsPeriod,
        customStart: Date,
        customEnd: Date,
        selectedMonth: Date,
        selectedCategoryID: String?,
        selectedVehicleID: UUID?
    ) -> StatsDisplaySnapshot {
        let selectedInterval = StatsViewModel.interval(
            for: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth
        )
        let previousInterval: DateInterval = {
            if selectedPeriod == .month {
                return StatsViewModel.previousMonthInterval(containing: selectedMonth)
            }
            return StatsViewModel.previousInterval(for: selectedInterval)
        }()

        let periodTrips = StatsViewModel.trips(in: selectedInterval, from: completedTrips)
        let previousTrips = StatsViewModel.trips(in: previousInterval, from: completedTrips)

        let stats = StatsViewModel.stats(
            for: periodTrips,
            categoryID: selectedCategoryID,
            vehicleID: selectedVehicleID
        )
        let previousStats = StatsViewModel.stats(
            for: previousTrips,
            categoryID: selectedCategoryID,
            vehicleID: selectedVehicleID
        )

        let vehicleDistance = StatsViewModel.vehicleBreakdown(for: periodTrips, vehicles: vehicles)
        let vehicleDuration = StatsViewModel.vehicleDurationBreakdown(for: periodTrips, vehicles: vehicles)
        let showsVehicle = !vehicleDistance.isEmpty && (vehicles.count > 1 || vehicleDistance.count > 1)

        return StatsDisplaySnapshot(
            stats: stats,
            previousStats: previousStats,
            dailyDistance: StatsViewModel.dailyDistances(in: selectedInterval, from: completedTrips),
            dailyDuration: StatsViewModel.dailyDurations(in: selectedInterval, from: completedTrips),
            dailyAverageSpeed: StatsViewModel.dailyAverageSpeeds(in: selectedInterval, from: completedTrips),
            dailyMaxSpeed: StatsViewModel.dailyMaxSpeeds(in: selectedInterval, from: completedTrips),
            categoryDistance: StatsViewModel.categoryBreakdown(for: periodTrips, categories: categories),
            categoryDuration: StatsViewModel.categoryDurationBreakdown(for: periodTrips, categories: categories),
            vehicleDistance: vehicleDistance,
            vehicleDuration: vehicleDuration,
            showsVehicleBreakdownCharts: showsVehicle
        )
    }
}
