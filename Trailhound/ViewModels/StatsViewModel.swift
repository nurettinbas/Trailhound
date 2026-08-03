import Foundation
import SwiftData

struct DailyDistance: Identifiable, Sendable {
    let id: Date
    let day: Date
    let distanceMeters: Double

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct DailyDuration: Identifiable, Sendable {
    let id: Date
    let day: Date
    let duration: TimeInterval

    var durationHours: Double { duration / 3600 }
}

struct DailyAverageSpeed: Identifiable, Sendable {
    let id: Date
    let day: Date
    let speedKmh: Double
}

struct DailyMaxSpeed: Identifiable, Sendable {
    let id: Date
    let day: Date
    let speedKmh: Double
}

struct DailyFuelCost: Identifiable, Sendable {
    let id: Date
    let day: Date
    let cost: Double
}

struct CategoryDistance: Identifiable, Sendable {
    let id: String
    let name: String
    let distanceMeters: Double

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct CategoryDuration: Identifiable, Sendable {
    let id: String
    let name: String
    let duration: TimeInterval

    var durationHours: Double { duration / 3600 }
}

struct CategoryFuelCost: Identifiable, Sendable {
    let id: String
    let name: String
    let cost: Double
}

struct VehicleDistance: Identifiable, Sendable {
    let id: String
    let name: String
    let distanceMeters: Double

    static let unassignedID = "unassigned"

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct VehicleDuration: Identifiable, Sendable {
    let id: String
    let name: String
    let duration: TimeInterval

    static let unassignedID = VehicleDistance.unassignedID

    var durationHours: Double { duration / 3600 }
}

struct VehicleFuelCost: Identifiable, Sendable {
    let id: String
    let name: String
    let cost: Double

    static let unassignedID = VehicleDistance.unassignedID
}

enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: L10n.string("stats.period.week")
        case .month: L10n.string("stats.period.month")
        case .custom: L10n.string("stats.period.custom")
        }
    }
}

struct StatsViewModel {
    /// - Parameter includeNightRatio: Walking every GPS point is orders of magnitude more expensive
    ///   than the other aggregations. Callers that only read distance/duration must pass `false`.
    static func stats<T: TripStatsAggregable>(
        for trips: [T],
        categoryID: String? = nil,
        vehicleID: UUID? = nil,
        includeNightRatio: Bool = true
    ) -> TripStats {
        let completed = trips.filter { trip in
            guard trip.endedAt != nil else { return false }
            if let categoryID, trip.categoryID != categoryID { return false }
            if let vehicleID, trip.vehicleID != vehicleID { return false }
            return true
        }

        let totalDistance = completed.reduce(0) { $0 + $1.distanceMeters }
        let totalDuration = completed.compactMap(\.duration).reduce(0, +)
        let totalFuel = completed.reduce(0) { partial, trip in
            partial + trip.resolvedFuelCost
        }
        let count = completed.reduce(0) { $0 + $1.tripCount }
        let averageDuration = count > 0 ? totalDuration / Double(count) : 0
        let averageSpeedKmh = averageSpeedKmh(distanceMeters: totalDistance, duration: totalDuration)
        // Vetted rather than derived from points: statistics span thousands of trips, and a
        // single phantom reading would otherwise become the headline figure for the period.
        let maxSpeedKmh = completed
            .compactMap { TripSpeedSummary.believableStoredMaxSpeedMps($0.maxSpeedMps) }
            .map { $0 * 3.6 }
            .max() ?? 0
        let nightRatio = includeNightRatio ? nightDrivingRatio(for: completed) : 0

        return TripStats(
            tripCount: count,
            totalDistanceMeters: totalDistance,
            totalDuration: totalDuration,
            averageDuration: averageDuration,
            averageSpeedKmh: averageSpeedKmh,
            maxSpeedKmh: maxSpeedKmh,
            estimatedFuelCost: totalFuel,
            nightDrivingRatio: nightRatio
        )
    }

    static func averageSpeedKmh(distanceMeters: Double, duration: TimeInterval) -> Double {
        guard duration > 0, distanceMeters > 0 else { return 0 }
        let kmh = distanceMeters * 3.6 / duration
        return kmh > 0 ? kmh : 0
    }

    static func fuelCost(for trip: Trip) -> Double {
        if let cost = trip.estimatedFuelCost, cost > 0 {
            return cost
        }
        guard trip.distanceMeters > 0 else { return 0 }
        return FuelCostCalculator.estimateCost(for: trip)
    }

    static func trips<T: TripStatsAggregable>(in interval: DateInterval, from trips: [T]) -> [T] {
        trips.filter { trip in
            guard let endedAt = trip.endedAt else { return false }
            return interval.contains(trip.startedAt) || interval.contains(endedAt)
        }
    }

    static func interval(
        for period: StatsPeriod,
        customStart: Date,
        customEnd: Date,
        selectedMonth: Date = Date()
    ) -> DateInterval {
        let calendar = Calendar.current
        let end = Date()
        switch period {
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
            return DateInterval(start: start, end: end)
        case .month:
            return calendarMonthInterval(containing: selectedMonth, calendar: calendar)
        case .custom:
            let start = min(customStart, customEnd)
            let finish = max(customStart, customEnd)
            return DateInterval(start: start, end: finish)
        }
    }

    /// Half-open calendar month `[startOfMonth, startOfNextMonth)`.
    static func calendarMonthInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let components = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: components) ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return DateInterval(start: start, end: end)
    }

    /// Calendar midnights crossed by `interval`, not `duration / 86400` (DST-safe).
    static func calendarDayCount(
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> Int {
        let start = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(days, 1)
    }

    static func calendarDaysInMonth(
        containing date: Date,
        calendar: Calendar = .current
    ) -> Int {
        calendarDayCount(in: calendarMonthInterval(containing: date, calendar: calendar), calendar: calendar)
    }

    static func shiftMonth(_ date: Date, by value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: value, to: calendarMonthInterval(containing: date, calendar: calendar).start)
            ?? date
    }

    /// Calendar month the goal ring tracks for the active filter.
    /// Week → current month; month → selected month; custom → month of the range end.
    static func goalMonth(
        for period: StatsPeriod,
        selectedMonth: Date,
        customStart: Date,
        customEnd: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        switch period {
        case .week:
            return calendarMonthInterval(containing: now, calendar: calendar).start
        case .month:
            return calendarMonthInterval(containing: selectedMonth, calendar: calendar).start
        case .custom:
            let end = max(customStart, customEnd)
            return calendarMonthInterval(containing: end, calendar: calendar).start
        }
    }

    /// Months from the first trip's month through the current month, newest first.
    /// With no trips, only the current month is offered.
    static func selectableMonths(
        earliestTripStart: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        let currentStart = calendarMonthInterval(containing: now, calendar: calendar).start
        let earliestStart: Date = {
            guard let earliestTripStart else { return currentStart }
            return calendarMonthInterval(containing: earliestTripStart, calendar: calendar).start
        }()

        guard earliestStart <= currentStart else { return [currentStart] }

        var months: [Date] = []
        var cursor = currentStart
        while cursor >= earliestStart {
            months.append(cursor)
            guard let previous = calendar.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return months
    }

    /// Ensures `month` is one of the selectable month starts (no duplicate picker rows).
    static func clampedMonth(
        _ month: Date,
        earliestTripStart: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let months = selectableMonths(
            earliestTripStart: earliestTripStart,
            now: now,
            calendar: calendar
        )
        let normalized = calendarMonthInterval(containing: month, calendar: calendar).start
        if let exact = months.first(where: { calendar.isDate($0, equalTo: normalized, toGranularity: .month) }) {
            return exact
        }
        return months.first ?? normalized
    }

    static func previousInterval(for interval: DateInterval) -> DateInterval {
        let duration = interval.duration
        let start = interval.start.addingTimeInterval(-duration)
        return DateInterval(start: start, end: interval.start)
    }

    static func previousMonthInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let previous = shiftMonth(date, by: -1, calendar: calendar)
        return calendarMonthInterval(containing: previous, calendar: calendar)
    }

    static func trendPercent(current: Double, previous: Double) -> Double? {
        guard previous > 0 else { return current > 0 ? 100 : nil }
        return ((current - previous) / previous) * 100
    }

    static func trendText(current: Double, previous: Double) -> String? {
        guard let percent = trendPercent(current: current, previous: previous) else { return nil }
        let format = L10n.string("stats.trend.format")
        let sign = percent > 0 ? "+" : ""
        return String(format: format, sign, Int(percent.rounded()))
    }

    static func dailyDistances<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyDistance] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var buckets: [Date: Double] = [:]

        var day = calendar.startOfDay(for: interval.start)
        let endDay = calendar.startOfDay(for: interval.end)
        while day <= endDay {
            buckets[day] = 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        for trip in filtered {
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            buckets[tripDay, default: 0] += trip.distanceMeters
        }

        return buckets.keys.sorted().map { day in
            DailyDistance(id: day, day: day, distanceMeters: buckets[day] ?? 0)
        }
    }

    static func dailyDurations<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyDuration] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var buckets: [Date: TimeInterval] = [:]

        var day = calendar.startOfDay(for: interval.start)
        let endDay = calendar.startOfDay(for: interval.end)
        while day <= endDay {
            buckets[day] = 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        for trip in filtered {
            guard let duration = trip.duration, duration > 0 else { continue }
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            buckets[tripDay, default: 0] += duration
        }

        return buckets.keys.sorted().map { day in
            DailyDuration(id: day, day: day, duration: buckets[day] ?? 0)
        }
    }

    static func dailyAverageSpeeds<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyAverageSpeed] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var distanceBuckets: [Date: Double] = [:]
        var durationBuckets: [Date: TimeInterval] = [:]

        var day = calendar.startOfDay(for: interval.start)
        let endDay = calendar.startOfDay(for: interval.end)
        while day <= endDay {
            distanceBuckets[day] = 0
            durationBuckets[day] = 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        for trip in filtered {
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            distanceBuckets[tripDay, default: 0] += trip.distanceMeters
            if let duration = trip.duration, duration > 0 {
                durationBuckets[tripDay, default: 0] += duration
            }
        }

        return distanceBuckets.keys.sorted().map { day in
            let speed = averageSpeedKmh(
                distanceMeters: distanceBuckets[day] ?? 0,
                duration: durationBuckets[day] ?? 0
            )
            return DailyAverageSpeed(id: day, day: day, speedKmh: speed)
        }
    }

    static func dailyMaxSpeeds<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyMaxSpeed] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var buckets: [Date: Double] = [:]

        var day = calendar.startOfDay(for: interval.start)
        let endDay = calendar.startOfDay(for: interval.end)
        while day <= endDay {
            buckets[day] = 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        for trip in filtered {
            guard let maxSpeedMps = TripSpeedSummary.believableStoredMaxSpeedMps(trip.maxSpeedMps) else {
                continue
            }
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            buckets[tripDay, default: 0] = max(buckets[tripDay, default: 0], maxSpeedMps * 3.6)
        }

        return buckets.keys.sorted().map { day in
            DailyMaxSpeed(id: day, day: day, speedKmh: buckets[day] ?? 0)
        }
    }

    static func dailyFuelCosts<T: TripStatsAggregable>(
        in interval: DateInterval,
        from trips: [T]
    ) -> [DailyFuelCost] {
        let calendar = Calendar.current
        let filtered = Self.trips(in: interval, from: trips)
        var buckets: [Date: Double] = [:]

        var day = calendar.startOfDay(for: interval.start)
        let endDay = calendar.startOfDay(for: interval.end)
        while day <= endDay {
            buckets[day] = 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        for trip in filtered {
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            buckets[tripDay, default: 0] += trip.resolvedFuelCost
        }

        return buckets.keys.sorted().map { day in
            DailyFuelCost(id: day, day: day, cost: buckets[day] ?? 0)
        }
    }

    /// Display names for every category key, resolved up front so the breakdowns can run away
    /// from the main actor without touching `UserCategory` models.
    static func categoryNameMap(for categories: [UserCategory]) -> StatsNameMap {
        var names: [String: String] = [:]
        for category in categories {
            names[category.storageKey] = category.name
        }
        for legacy in TripCategory.allCases {
            names[legacy.rawValue] = names[legacy.rawValue] ?? legacy.displayName
        }
        return StatsNameMap(names: names, fallback: L10n.string("label.other"))
    }

    static func vehicleNameMap(for vehicles: [VehicleProfile]) -> StatsNameMap {
        var names: [String: String] = [:]
        for vehicle in vehicles {
            names[vehicle.id.uuidString] = vehicle.name
        }
        names[VehicleDistance.unassignedID] = L10n.string("stats.vehicle.unassigned")
        return StatsNameMap(names: names, fallback: L10n.string("stats.vehicle.unknown"))
    }

    static func categoryBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categoryNames: StatsNameMap
    ) -> [CategoryDistance] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: Double] = [:]

        for trip in filtered {
            totals[trip.categoryID, default: 0] += trip.distanceMeters
        }

        return totals.map { key, distance in
            CategoryDistance(id: key, name: categoryNames.name(for: key), distanceMeters: distance)
        }
        .sorted { $0.distanceMeters > $1.distanceMeters }
    }

    static func categoryDurationBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categoryNames: StatsNameMap
    ) -> [CategoryDuration] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: TimeInterval] = [:]

        for trip in filtered {
            guard let duration = trip.duration, duration > 0 else { continue }
            totals[trip.categoryID, default: 0] += duration
        }

        return totals.map { key, duration in
            CategoryDuration(id: key, name: categoryNames.name(for: key), duration: duration)
        }
        .sorted { $0.duration > $1.duration }
    }

    static func vehicleBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicleNames: StatsNameMap
    ) -> [VehicleDistance] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: Double] = [:]

        for trip in filtered {
            let key = trip.vehicleID?.uuidString ?? VehicleDistance.unassignedID
            totals[key, default: 0] += trip.distanceMeters
        }

        return totals.map { key, distance in
            VehicleDistance(id: key, name: vehicleNames.name(for: key), distanceMeters: distance)
        }
        .sorted { $0.distanceMeters > $1.distanceMeters }
    }

    static func vehicleDurationBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicleNames: StatsNameMap
    ) -> [VehicleDuration] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: TimeInterval] = [:]

        for trip in filtered {
            guard let duration = trip.duration, duration > 0 else { continue }
            let key = trip.vehicleID?.uuidString ?? VehicleDuration.unassignedID
            totals[key, default: 0] += duration
        }

        return totals.map { key, duration in
            VehicleDuration(id: key, name: vehicleNames.name(for: key), duration: duration)
        }
        .sorted { $0.duration > $1.duration }
    }

    static func categoryFuelBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categoryNames: StatsNameMap
    ) -> [CategoryFuelCost] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: Double] = [:]

        for trip in filtered {
            totals[trip.categoryID, default: 0] += trip.resolvedFuelCost
        }

        return totals.map { key, cost in
            CategoryFuelCost(id: key, name: categoryNames.name(for: key), cost: cost)
        }
        .sorted { $0.cost > $1.cost }
    }

    static func vehicleFuelBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicleNames: StatsNameMap
    ) -> [VehicleFuelCost] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: Double] = [:]

        for trip in filtered {
            let key = trip.vehicleID?.uuidString ?? VehicleFuelCost.unassignedID
            totals[key, default: 0] += trip.resolvedFuelCost
        }

        return totals.map { key, cost in
            VehicleFuelCost(id: key, name: vehicleNames.name(for: key), cost: cost)
        }
        .sorted { $0.cost > $1.cost }
    }

    static func categoryBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categories: [UserCategory]
    ) -> [CategoryDistance] {
        categoryBreakdown(for: trips, categoryNames: categoryNameMap(for: categories))
    }

    static func categoryDurationBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categories: [UserCategory]
    ) -> [CategoryDuration] {
        categoryDurationBreakdown(for: trips, categoryNames: categoryNameMap(for: categories))
    }

    static func categoryFuelBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        categories: [UserCategory]
    ) -> [CategoryFuelCost] {
        categoryFuelBreakdown(for: trips, categoryNames: categoryNameMap(for: categories))
    }

    static func vehicleBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicles: [VehicleProfile]
    ) -> [VehicleDistance] {
        vehicleBreakdown(for: trips, vehicleNames: vehicleNameMap(for: vehicles))
    }

    static func vehicleDurationBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicles: [VehicleProfile]
    ) -> [VehicleDuration] {
        vehicleDurationBreakdown(for: trips, vehicleNames: vehicleNameMap(for: vehicles))
    }

    static func vehicleFuelBreakdown<T: TripStatsAggregable>(
        for trips: [T],
        vehicles: [VehicleProfile]
    ) -> [VehicleFuelCost] {
        vehicleFuelBreakdown(for: trips, vehicleNames: vehicleNameMap(for: vehicles))
    }

    static func nightDrivingRatio<T: TripStatsAggregable>(for trips: [T]) -> Double {
        var nightMeters = 0.0
        var totalMeters = 0.0

        for trip in trips {
            guard let share = trip.nightDistanceShare else { continue }
            nightMeters += share.nightMeters
            totalMeters += share.trackedMeters
        }

        guard totalMeters > 0 else { return 0 }
        return nightMeters / totalMeters
    }

    /// Fallback for trips whose derived split has not been backfilled yet. Walks every GPS
    /// segment, so it is the one path that still scales with recorded point count.
    static func walkNightDistanceShare(for trip: Trip) -> NightDistanceShare? {
        PerformanceSignposts.measure("NightDistanceWalk") {
            let points = trip.sortedPoints
            guard points.count >= 2 else { return nil }

            // Resolving the UTC offset once per trip keeps DST correctness without paying
            // `Calendar.component(.hour:)` on every GPS segment.
            let utcOffset = Double(TimeZone.current.secondsFromGMT(for: trip.startedAt))
            var nightMeters = 0.0
            var totalMeters = 0.0

            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let segment = approximateDistanceMeters(
                    fromLatitude: previous.latitude,
                    fromLongitude: previous.longitude,
                    toLatitude: current.latitude,
                    toLongitude: current.longitude
                )
                guard segment > 0 else { continue }

                let previousTime = previous.timestamp.timeIntervalSince1970
                let midpoint = previousTime
                    + (current.timestamp.timeIntervalSince1970 - previousTime) / 2
                totalMeters += segment
                if isNightTimestamp(midpoint, utcOffset: utcOffset) {
                    nightMeters += segment
                }
            }

            return NightDistanceShare(nightMeters: nightMeters, trackedMeters: totalMeters)
        }
    }

    /// Equirectangular approximation. Consecutive GPS samples are metres apart, so the error
    /// against the geodesic stays far below the noise floor of the samples themselves — and it
    /// avoids allocating two `CLLocation` objects per segment.
    static func approximateDistanceMeters(
        fromLatitude latitude1: Double,
        fromLongitude longitude1: Double,
        toLatitude latitude2: Double,
        toLongitude longitude2: Double
    ) -> Double {
        let metersPerDegree = 111_320.0
        let meanLatitudeRadians = ((latitude1 + latitude2) / 2) * .pi / 180
        let deltaLatitude = (latitude2 - latitude1) * metersPerDegree
        let deltaLongitude = (longitude2 - longitude1) * metersPerDegree * cos(meanLatitudeRadians)
        return (deltaLatitude * deltaLatitude + deltaLongitude * deltaLongitude).squareRoot()
    }

    static func nightDrivingPercentText(for ratio: Double) -> String {
        let percent = Int((ratio * 100).rounded())
        let format = L10n.string("stats.night_driving.format")
        return String(format: format, percent)
    }

    /// Night is 22:00–06:00 local time. `utcOffset` is resolved once per trip rather than per
    /// segment, which keeps DST correctness without paying `Calendar.component(.hour:)` per point.
    static func isNightTimestamp(_ timeIntervalSince1970: Double, utcOffset: Double) -> Bool {
        let secondsInDay = (timeIntervalSince1970 + utcOffset).truncatingRemainder(dividingBy: 86_400)
        let normalized = secondsInDay < 0 ? secondsInDay + 86_400 : secondsInDay
        let hour = Int(normalized / 3_600)
        return hour >= 22 || hour < 6
    }
}

struct TripStats: Sendable {
    let tripCount: Int
    let totalDistanceMeters: Double
    let totalDuration: TimeInterval
    let averageDuration: TimeInterval
    let averageSpeedKmh: Double
    let maxSpeedKmh: Double
    let estimatedFuelCost: Double
    let nightDrivingRatio: Double

    init(
        tripCount: Int,
        totalDistanceMeters: Double,
        totalDuration: TimeInterval,
        averageDuration: TimeInterval,
        averageSpeedKmh: Double = 0,
        maxSpeedKmh: Double = 0,
        estimatedFuelCost: Double,
        nightDrivingRatio: Double = 0
    ) {
        self.tripCount = tripCount
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDuration = totalDuration
        self.averageDuration = averageDuration
        self.averageSpeedKmh = averageSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.estimatedFuelCost = estimatedFuelCost
        self.nightDrivingRatio = nightDrivingRatio
    }

    var totalDistanceText: String { DateFormatters.formatDistance(totalDistanceMeters) }
    var totalDurationText: String { DateFormatters.formatDuration(totalDuration) }
    var averageDurationText: String { DateFormatters.formatDuration(averageDuration) }
    var averageSpeedText: String {
        averageSpeedKmh > 0 ? L10n.formatSpeedKmh(averageSpeedKmh) : "—"
    }
    var maxSpeedText: String {
        maxSpeedKmh > 0 ? L10n.formatSpeedKmh(maxSpeedKmh) : "—"
    }
    var fuelCostText: String { FuelCostCalculator.formatCost(estimatedFuelCost) }
    var nightDrivingText: String { StatsViewModel.nightDrivingPercentText(for: nightDrivingRatio) }

    var costPerKm: Double {
        let kilometers = totalDistanceMeters / 1000
        guard kilometers > 0, estimatedFuelCost > 0 else { return 0 }
        return estimatedFuelCost / kilometers
    }

    var averageCostPerTrip: Double {
        guard tripCount > 0, estimatedFuelCost > 0 else { return 0 }
        return estimatedFuelCost / Double(tripCount)
    }

    var costPerKmText: String {
        costPerKm > 0 ? FuelCostCalculator.formatCost(costPerKm) : "—"
    }

    var averageCostPerTripText: String {
        averageCostPerTrip > 0 ? FuelCostCalculator.formatCost(averageCostPerTrip) : "—"
    }
}
