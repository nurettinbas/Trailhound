import Foundation
import SwiftData

struct StatsDisplaySnapshot: Sendable {
    let stats: TripStats
    let previousStats: TripStats
    let dailyDistance: [DailyDistance]
    let dailyDuration: [DailyDuration]
    let dailyAverageSpeed: [DailyAverageSpeed]
    let dailyMaxSpeed: [DailyMaxSpeed]
    let dailyFuelCost: [DailyFuelCost]
    let categoryDistance: [CategoryDistance]
    let categoryDuration: [CategoryDuration]
    let categoryFuelCost: [CategoryFuelCost]
    let vehicleDistance: [VehicleDistance]
    let vehicleDuration: [VehicleDuration]
    let vehicleFuelCost: [VehicleFuelCost]
    let showsVehicleBreakdownCharts: Bool
    /// Distance driven in the goal calendar month (no category/vehicle/place filter). Drives the goal ring.
    let goalDistanceMeters: Double

    var hasAnyDailyChart: Bool {
        !dailyDistance.isEmpty || !dailyDuration.isEmpty
            || !dailyAverageSpeed.isEmpty || !dailyMaxSpeed.isEmpty
            || !dailyFuelCost.isEmpty
    }

    var hasCategoryCharts: Bool {
        !categoryDistance.isEmpty || !categoryDuration.isEmpty || !categoryFuelCost.isEmpty
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
        dailyFuelCost: [],
        categoryDistance: [],
        categoryDuration: [],
        categoryFuelCost: [],
        vehicleDistance: [],
        vehicleDuration: [],
        vehicleFuelCost: [],
        showsVehicleBreakdownCharts: false,
        goalDistanceMeters: 0
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

    func fuelCostTrendText() -> String? {
        StatsViewModel.trendText(
            current: stats.estimatedFuelCost,
            previous: previousStats.estimatedFuelCost
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
        selectedVehicleID: UUID?,
        selectedPlaceName: String? = nil,
        goalMonth: Date
    ) -> StatsDisplaySnapshot {
        build(
            completedTrips: completedTrips.map(TripStatsRow.init(trip:)),
            categoryNames: StatsViewModel.categoryNameMap(for: categories),
            vehicleNames: StatsViewModel.vehicleNameMap(for: vehicles),
            vehicleCount: vehicles.count,
            selectedPeriod: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth,
            selectedCategoryID: selectedCategoryID,
            selectedVehicleID: selectedVehicleID,
            selectedPlaceName: selectedPlaceName,
            goalMonth: goalMonth
        )
    }

    /// Runs off the main actor: every input is a plain value, so nothing here touches SwiftData.
    nonisolated static func build(
        completedTrips: [TripStatsRow],
        categoryNames: StatsNameMap,
        vehicleNames: StatsNameMap,
        vehicleCount: Int,
        selectedPeriod: StatsPeriod,
        customStart: Date,
        customEnd: Date,
        selectedMonth: Date,
        selectedCategoryID: String?,
        selectedVehicleID: UUID?,
        selectedPlaceName: String? = nil,
        goalMonth: Date
    ) -> StatsDisplaySnapshot {
        PerformanceSignposts.measure("StatsSnapshotBuild") {
            buildUnmeasured(
                completedTrips: completedTrips,
                categoryNames: categoryNames,
                vehicleNames: vehicleNames,
                vehicleCount: vehicleCount,
                selectedPeriod: selectedPeriod,
                customStart: customStart,
                customEnd: customEnd,
                selectedMonth: selectedMonth,
                selectedCategoryID: selectedCategoryID,
                selectedVehicleID: selectedVehicleID,
                selectedPlaceName: selectedPlaceName,
                goalMonth: goalMonth
            )
        }
    }

    nonisolated private static func buildUnmeasured(
        completedTrips: [TripStatsRow],
        categoryNames: StatsNameMap,
        vehicleNames: StatsNameMap,
        vehicleCount: Int,
        selectedPeriod: StatsPeriod,
        customStart: Date,
        customEnd: Date,
        selectedMonth: Date,
        selectedCategoryID: String?,
        selectedVehicleID: UUID?,
        selectedPlaceName: String?,
        goalMonth: Date
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

        // Summary + charts share the same category/vehicle/place scope. The goal ring stays
        // unfiltered so monthly progress is never shrunk by a chip selection.
        let scopedTrips = StatsViewModel.filtered(
            completedTrips,
            categoryID: selectedCategoryID,
            vehicleID: selectedVehicleID,
            placeName: selectedPlaceName
        )
        let periodTrips = StatsViewModel.trips(in: selectedInterval, from: scopedTrips)
        let previousTrips = StatsViewModel.trips(in: previousInterval, from: scopedTrips)

        let stats = StatsViewModel.stats(for: periodTrips)
        let previousStats = StatsViewModel.stats(for: previousTrips)

        let vehicleDistance = StatsViewModel.vehicleBreakdown(for: periodTrips, vehicleNames: vehicleNames)
        let vehicleDuration = StatsViewModel.vehicleDurationBreakdown(for: periodTrips, vehicleNames: vehicleNames)
        let vehicleFuelCost = StatsViewModel.vehicleFuelBreakdown(for: periodTrips, vehicleNames: vehicleNames)
        let showsVehicle = !vehicleDistance.isEmpty && (vehicleCount > 1 || vehicleDistance.count > 1)

        // Goal ring always tracks a full calendar month — never the week/custom window or filters.
        let goalMonthInterval = StatsViewModel.calendarMonthInterval(containing: goalMonth)
        let goalDistance = StatsViewModel.stats(
            for: StatsViewModel.trips(in: goalMonthInterval, from: completedTrips),
            includeNightRatio: false
        ).totalDistanceMeters

        return StatsDisplaySnapshot(
            stats: stats,
            previousStats: previousStats,
            dailyDistance: StatsViewModel.dailyDistances(in: selectedInterval, from: scopedTrips),
            dailyDuration: StatsViewModel.dailyDurations(in: selectedInterval, from: scopedTrips),
            dailyAverageSpeed: StatsViewModel.dailyAverageSpeeds(in: selectedInterval, from: scopedTrips),
            dailyMaxSpeed: StatsViewModel.dailyMaxSpeeds(in: selectedInterval, from: scopedTrips),
            dailyFuelCost: StatsViewModel.dailyFuelCosts(in: selectedInterval, from: scopedTrips),
            categoryDistance: StatsViewModel.categoryBreakdown(for: periodTrips, categoryNames: categoryNames),
            categoryDuration: StatsViewModel.categoryDurationBreakdown(for: periodTrips, categoryNames: categoryNames),
            categoryFuelCost: StatsViewModel.categoryFuelBreakdown(for: periodTrips, categoryNames: categoryNames),
            vehicleDistance: vehicleDistance,
            vehicleDuration: vehicleDuration,
            vehicleFuelCost: vehicleFuelCost,
            showsVehicleBreakdownCharts: showsVehicle,
            goalDistanceMeters: goalDistance
        )
    }
}
