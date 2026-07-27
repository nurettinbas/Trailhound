import CoreLocation
import Foundation
import SwiftData

struct DailyDistance: Identifiable {
    let id: Date
    let day: Date
    let distanceMeters: Double

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct DailyDuration: Identifiable {
    let id: Date
    let day: Date
    let duration: TimeInterval

    var durationHours: Double { duration / 3600 }
}

struct DailyAverageSpeed: Identifiable {
    let id: Date
    let day: Date
    let speedKmh: Double
}

struct DailyMaxSpeed: Identifiable {
    let id: Date
    let day: Date
    let speedKmh: Double
}

struct CategoryDistance: Identifiable {
    let id: String
    let name: String
    let distanceMeters: Double

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct CategoryDuration: Identifiable {
    let id: String
    let name: String
    let duration: TimeInterval

    var durationHours: Double { duration / 3600 }
}

struct VehicleDistance: Identifiable {
    let id: String
    let name: String
    let distanceMeters: Double

    static let unassignedID = "unassigned"

    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct VehicleDuration: Identifiable {
    let id: String
    let name: String
    let duration: TimeInterval

    static let unassignedID = VehicleDistance.unassignedID

    var durationHours: Double { duration / 3600 }
}

enum StatsPeriod: String, CaseIterable, Identifiable {
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
    static func stats(for trips: [Trip], categoryID: String? = nil, vehicleID: UUID? = nil) -> TripStats {
        let completed = trips.filter { trip in
            guard trip.endedAt != nil else { return false }
            if let categoryID, trip.categoryID != categoryID { return false }
            if let vehicleID, trip.vehicleID != vehicleID { return false }
            return true
        }

        let totalDistance = completed.reduce(0) { $0 + $1.distanceMeters }
        let totalDuration = completed.compactMap(\.duration).reduce(0, +)
        let totalFuel = completed.reduce(0) { partial, trip in
            partial + fuelCost(for: trip)
        }
        let count = completed.count
        let averageDuration = count > 0 ? totalDuration / Double(count) : 0
        let averageSpeedKmh = averageSpeedKmh(distanceMeters: totalDistance, duration: totalDuration)
        let maxSpeedKmh = completed.compactMap(\.maxSpeedMps).filter { $0 > 0 }.map { $0 * 3.6 }.max() ?? 0
        let nightRatio = nightDrivingRatio(for: completed)

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

    static func trips(in interval: DateInterval, from trips: [Trip]) -> [Trip] {
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

    static func shiftMonth(_ date: Date, by value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: value, to: calendarMonthInterval(containing: date, calendar: calendar).start)
            ?? date
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

    static func dailyDistances(in interval: DateInterval, from trips: [Trip]) -> [DailyDistance] {
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

    static func dailyDurations(in interval: DateInterval, from trips: [Trip]) -> [DailyDuration] {
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

    static func dailyAverageSpeeds(in interval: DateInterval, from trips: [Trip]) -> [DailyAverageSpeed] {
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

    static func dailyMaxSpeeds(in interval: DateInterval, from trips: [Trip]) -> [DailyMaxSpeed] {
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
            guard let maxSpeedMps = trip.maxSpeedMps, maxSpeedMps > 0 else { continue }
            let tripDay = calendar.startOfDay(for: trip.startedAt)
            buckets[tripDay, default: 0] = max(buckets[tripDay, default: 0], maxSpeedMps * 3.6)
        }

        return buckets.keys.sorted().map { day in
            DailyMaxSpeed(id: day, day: day, speedKmh: buckets[day] ?? 0)
        }
    }

    static func categoryBreakdown(for trips: [Trip], categories: [UserCategory]) -> [CategoryDistance] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: Double] = [:]

        for trip in filtered {
            totals[trip.categoryID, default: 0] += trip.distanceMeters
        }

        return totals.map { key, distance in
            let name = categories.first(where: { $0.storageKey == key })?.name
                ?? TripCategory(rawValue: key)?.displayName
                ?? L10n.string("label.other")
            return CategoryDistance(id: key, name: name, distanceMeters: distance)
        }
        .sorted { $0.distanceMeters > $1.distanceMeters }
    }

    static func categoryDurationBreakdown(for trips: [Trip], categories: [UserCategory]) -> [CategoryDuration] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: TimeInterval] = [:]

        for trip in filtered {
            guard let duration = trip.duration, duration > 0 else { continue }
            totals[trip.categoryID, default: 0] += duration
        }

        return totals.map { key, duration in
            let name = categories.first(where: { $0.storageKey == key })?.name
                ?? TripCategory(rawValue: key)?.displayName
                ?? L10n.string("label.other")
            return CategoryDuration(id: key, name: name, duration: duration)
        }
        .sorted { $0.duration > $1.duration }
    }

    static func vehicleBreakdown(for trips: [Trip], vehicles: [VehicleProfile]) -> [VehicleDistance] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: Double] = [:]

        for trip in filtered {
            let key = trip.vehicleID?.uuidString ?? VehicleDistance.unassignedID
            totals[key, default: 0] += trip.distanceMeters
        }

        return totals.map { key, distance in
            let name: String
            if key == VehicleDistance.unassignedID {
                name = L10n.string("stats.vehicle.unassigned")
            } else if let id = UUID(uuidString: key),
                      let vehicle = vehicles.first(where: { $0.id == id }) {
                name = vehicle.name
            } else {
                name = L10n.string("stats.vehicle.unknown")
            }
            return VehicleDistance(id: key, name: name, distanceMeters: distance)
        }
        .sorted { $0.distanceMeters > $1.distanceMeters }
    }

    static func vehicleDurationBreakdown(for trips: [Trip], vehicles: [VehicleProfile]) -> [VehicleDuration] {
        let filtered = trips.filter { $0.endedAt != nil }
        var totals: [String: TimeInterval] = [:]

        for trip in filtered {
            guard let duration = trip.duration, duration > 0 else { continue }
            let key = trip.vehicleID?.uuidString ?? VehicleDuration.unassignedID
            totals[key, default: 0] += duration
        }

        return totals.map { key, duration in
            let name: String
            if key == VehicleDuration.unassignedID {
                name = L10n.string("stats.vehicle.unassigned")
            } else if let id = UUID(uuidString: key),
                      let vehicle = vehicles.first(where: { $0.id == id }) {
                name = vehicle.name
            } else {
                name = L10n.string("stats.vehicle.unknown")
            }
            return VehicleDuration(id: key, name: name, duration: duration)
        }
        .sorted { $0.duration > $1.duration }
    }

    static func nightDrivingRatio(for trips: [Trip]) -> Double {
        var nightMeters = 0.0
        var totalMeters = 0.0
        let calendar = Calendar.current

        for trip in trips {
            let points = trip.sortedPoints
            guard points.count >= 2 else { continue }

            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let segment = previous.location.distance(from: current.location)
                guard segment > 0 else { continue }

                let midpoint = previous.timestamp.addingTimeInterval(
                    current.timestamp.timeIntervalSince(previous.timestamp) / 2
                )
                totalMeters += segment
                if isNightHour(midpoint, calendar: calendar) {
                    nightMeters += segment
                }
            }
        }

        guard totalMeters > 0 else { return 0 }
        return nightMeters / totalMeters
    }

    static func nightDrivingPercentText(for ratio: Double) -> String {
        let percent = Int((ratio * 100).rounded())
        let format = L10n.string("stats.night_driving.format")
        return String(format: format, percent)
    }

    private static func isNightHour(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 22 || hour < 6
    }
}

struct TripStats {
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
}
