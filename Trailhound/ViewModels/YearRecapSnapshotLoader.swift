import Foundation
import SwiftData

@ModelActor
actor YearRecapSnapshotLoader {
    private var cache: [Int: YearRecapSnapshot] = [:]
    private var cachedStoreVersion: Int?

    func snapshot(year: Int, storeVersion: Int, now: Date = Date()) -> YearRecapSnapshot {
        if cachedStoreVersion != storeVersion {
            cache.removeAll(keepingCapacity: true)
            cachedStoreVersion = storeVersion
        }
        if let cached = cache[year] { return cached }
        if let disk = YearRecapCache.load(year: year) {
            cache[year] = disk
            return disk
        }
        let built = build(year: year, now: now)
        cache[year] = built
        YearRecapCache.save(built)
        return built
    }

    func clearCache() {
        cache.removeAll(keepingCapacity: true)
        cachedStoreVersion = nil
    }

    private func build(year: Int, now: Date) -> YearRecapSnapshot {
        let calendar = Calendar.current
        guard
            let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
            let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart)
        else {
            return .empty(year: year)
        }

        let rollupDescriptor = FetchDescriptor<TripDailyRollup>(
            predicate: #Predicate { rollup in
                rollup.dayStart >= yearStart && rollup.dayStart < yearEnd
            }
        )
        let rollups = (try? modelContext.fetch(rollupDescriptor)) ?? []

        var distance = 0.0
        var duration = 0.0
        var tripCount = 0
        var night = 0.0
        var fuel = 0.0
        var businessDistance = 0.0
        var personalDistance = 0.0
        var monthDistance: [Int: Double] = [:]
        var activeDays = Set<Date>()

        let businessID = BuiltInCategory.businessID.uuidString
        let legacyBusiness = TripCategory.business.rawValue
        for rollup in rollups {
            distance += rollup.distanceMeters
            duration += rollup.duration
            tripCount += rollup.tripCount
            night += rollup.nightDistanceMeters
            fuel += rollup.estimatedFuelCost
            if rollup.categoryID == businessID || rollup.categoryID == legacyBusiness {
                businessDistance += rollup.distanceMeters
            } else {
                personalDistance += rollup.distanceMeters
            }
            let month = calendar.component(.month, from: rollup.dayStart)
            monthDistance[month, default: 0] += rollup.distanceMeters
            if rollup.tripCount > 0 {
                activeDays.insert(calendar.startOfDay(for: rollup.dayStart))
            }
        }

        let tripDescriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { trip in
                trip.endedAt != nil && trip.startedAt >= yearStart && trip.startedAt < yearEnd
            }
        )
        let trips = (try? modelContext.fetch(tripDescriptor)) ?? []
        var cityCounts: [String: Int] = [:]
        for trip in trips {
            for name in TripLocalityResolver.localities(on: trip) {
                cityCounts[name, default: 0] += 1
            }
            trip.invalidatePointCaches()
        }
        let topCities = cityCounts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.prefix(3).map(\.key)

        let routes = ((try? modelContext.fetch(FetchDescriptor<FrequentRouteAggregate>())) ?? [])
            .filter { $0.lastStartedAt >= yearStart && $0.lastStartedAt < yearEnd }
            .sorted { $0.count > $1.count }
        let topRoute = routes.first

        let expenseDescriptor = FetchDescriptor<VehicleExpense>(
            predicate: #Predicate { expense in
                expense.occurredAt >= yearStart && expense.occurredAt < yearEnd
            }
        )
        let paid = ((try? modelContext.fetch(expenseDescriptor)) ?? []).reduce(0) { $0 + $1.amount }

        let unlocked = ((try? modelContext.fetch(FetchDescriptor<AchievementProgress>())) ?? [])
            .compactMap { row -> String? in
                guard let unlockedAt = row.unlockedAt else { return nil }
                let unlockedYear = calendar.component(.year, from: unlockedAt)
                return unlockedYear == year ? row.achievementID : nil
            }

        let busiest = monthDistance.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }

        return YearRecapSnapshot(
            year: year,
            tripCount: tripCount,
            distanceMeters: distance,
            duration: duration,
            cityCount: cityCounts.count,
            topCities: Array(topCities),
            topRouteStart: topRoute?.startDisplay,
            topRouteEnd: topRoute?.endDisplay,
            topRouteCount: topRoute?.count ?? 0,
            topRouteStartLatitude: topRoute?.startLatitude,
            topRouteStartLongitude: topRoute?.startLongitude,
            topRouteEndLatitude: topRoute?.endLatitude,
            topRouteEndLongitude: topRoute?.endLongitude,
            nightDistanceMeters: night,
            longestStreak: longestStreak(in: activeDays, calendar: calendar),
            busiestMonth: busiest?.key,
            busiestMonthDistanceMeters: busiest?.value ?? 0,
            businessDistanceMeters: businessDistance,
            personalDistanceMeters: personalDistance,
            estimatedFuelCost: fuel,
            paidExpenses: paid,
            unlockedAchievementIDs: unlocked
        )
    }

    private func longestStreak(in days: Set<Date>, calendar: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()
        var best = 1
        var current = 1
        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let day = sorted[index]
            if let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(expected, inSameDayAs: day) {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }
}
