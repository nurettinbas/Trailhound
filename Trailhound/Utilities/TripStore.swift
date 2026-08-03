import Foundation
import SwiftData

@MainActor
enum TripStore {
    static func all(from context: ModelContext) -> [Trip] {
        (try? context.fetch(FetchDescriptor<Trip>())) ?? []
    }

    static func completed(from context: ModelContext) -> [Trip] {
        all(from: context).filter(isCompleted)
    }

    static func completedSince(_ date: Date, from context: ModelContext) -> [Trip] {
        let minimum = date.timeIntervalSinceReferenceDate
        return completed(from: context).filter { trip in
            trip.startedAt.timeIntervalSinceReferenceDate >= minimum
        }
    }

    static func completedBefore(_ date: Date, from context: ModelContext) -> [Trip] {
        let maximum = date.timeIntervalSinceReferenceDate
        return completed(from: context).filter { trip in
            trip.startedAt.timeIntervalSinceReferenceDate < maximum
        }
    }

    static func orphans(from context: ModelContext) -> [Trip] {
        all(from: context).filter { !isCompleted($0) }
    }

    static func orphansNewestFirst(from context: ModelContext) -> [Trip] {
        var trips = orphans(from: context)
        trips.sort { lhs, rhs in
            lhs.startedAt.timeIntervalSinceReferenceDate > rhs.startedAt.timeIntervalSinceReferenceDate
        }
        return trips
    }

    static func syncWidgetWeekDistance(in context: ModelContext) {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekTrips = StatsViewModel.trips(
            in: DateInterval(start: weekAgo, end: Date()),
            from: completedSince(weekAgo, from: context)
        )
        let stats = StatsViewModel.stats(for: weekTrips, includeNightRatio: false)
        let defaults = UserDefaults(suiteName: "group.com.trailhound.app")
        defaults?.set(stats.totalDistanceMeters, forKey: "stats.weekDistance")

        let monthInterval = StatsViewModel.calendarMonthInterval(containing: Date())
        let monthTrips = StatsViewModel.trips(
            in: monthInterval,
            from: completedSince(monthInterval.start, from: context)
        )
        defaults?.set(
            StatsViewModel.stats(for: monthTrips, includeNightRatio: false).totalDistanceMeters,
            forKey: "stats.monthDistance"
        )

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let todayTrips = completedSince(startOfDay, from: context)
        let todayDistance = todayTrips.reduce(0) { $0 + $1.distanceMeters }
        TodayKmProvider.syncTodayDistance(todayDistance)
    }

    private static func isCompleted(_ trip: Trip) -> Bool {
        trip.duration != nil
    }
}
