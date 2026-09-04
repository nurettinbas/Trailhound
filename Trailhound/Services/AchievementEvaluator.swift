import Foundation
import SwiftData

enum AchievementEvaluator {
    static func apply(
        trip: Trip,
        sign: Double,
        localities: [String],
        in context: ModelContext
    ) {
        guard trip.endedAt != nil else { return }
        bump(.firstTrip, by: sign, in: context)
        bump(.distance100, by: sign * trip.distanceMeters, in: context)
        bump(.distance1000, by: sign * trip.distanceMeters, in: context)
        bump(.distance10000, by: sign * trip.distanceMeters, in: context)
        if trip.categoryID == BuiltInCategory.businessID.uuidString {
            bump(.business10, by: sign, in: context)
            bump(.business50, by: sign, in: context)
        }
        bump(.nightOwl, by: sign * (trip.nightDistanceMeters ?? 0), in: context)
        applyLocalities(localities, sign: sign, in: context)
        refreshStreak(in: context)
        refreshRouteRegular(in: context)
    }

    static func displays(in context: ModelContext) -> [AchievementDisplay] {
        let rows = (try? context.fetch(FetchDescriptor<AchievementProgress>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.achievementID, $0) })
        let unlocked = Set(rows.compactMap { row -> AchievementID? in
            guard row.unlockedAt != nil else { return nil }
            return AchievementID(rawValue: row.achievementID)
        })
        return AchievementID.allCases.compactMap { id in
            if let predecessor = id.predecessor, !unlocked.contains(predecessor), byID[id.rawValue]?.unlockedAt == nil {
                return nil
            }
            let row = byID[id.rawValue]
            return AchievementDisplay(
                id: id,
                currentValue: row?.currentValue ?? 0,
                unlockedAt: row?.unlockedAt,
                needsCelebration: row?.needsCelebration ?? false
            )
        }
        .sorted { lhs, rhs in
            if lhs.isUnlocked != rhs.isUnlocked { return lhs.isUnlocked && !rhs.isUnlocked }
            return lhs.id.sortOrder < rhs.id.sortOrder
        }
    }

    static func markSeen(_ ids: [AchievementID], in context: ModelContext) {
        let names = Set(ids.map(\.rawValue))
        let rows = (try? context.fetch(FetchDescriptor<AchievementProgress>())) ?? []
        let now = Date()
        for row in rows where names.contains(row.achievementID) && row.needsCelebration {
            row.seenAt = now
        }
    }

    static func rebuild(in context: ModelContext) {
        for row in (try? context.fetch(FetchDescriptor<AchievementProgress>())) ?? [] {
            context.delete(row)
        }
        for row in (try? context.fetch(FetchDescriptor<VisitedLocality>())) ?? [] {
            context.delete(row)
        }

        let trips = ((try? context.fetch(FetchDescriptor<Trip>())) ?? []).filter { $0.endedAt != nil }
        for trip in trips {
            apply(trip: trip, sign: 1, localities: TripLocalityResolver.localities(on: trip), in: context)
        }
    }

    private static func bump(_ id: AchievementID, by delta: Double, in context: ModelContext) {
        guard delta != 0 else { return }
        let row = progress(for: id, in: context)
        row.currentValue = max(0, row.currentValue + delta)
        if row.unlockedAt == nil, row.currentValue + 0.000_1 >= id.threshold {
            row.unlockedAt = Date()
        }
    }

    private static func applyLocalities(_ localities: [String], sign: Double, in context: ModelContext) {
        guard sign != 0 else { return }
        for name in Set(localities) {
            let existing = locality(named: name, in: context)
            if sign > 0 {
                if let existing {
                    existing.visitCount += 1
                } else {
                    context.insert(VisitedLocality(name: name, visitCount: 1))
                }
            } else if let existing {
                existing.visitCount = max(0, existing.visitCount - 1)
                if existing.visitCount == 0 {
                    context.delete(existing)
                }
            }
        }
        let count = Double(((try? context.fetch(FetchDescriptor<VisitedLocality>())) ?? []).count)
        setValue(.cities10, count, in: context)
        setValue(.cities25, count, in: context)
    }

    private static func refreshStreak(in context: ModelContext) {
        let streak = currentStreakDays(in: context)
        setValue(.streak7, Double(streak), in: context)
        setValue(.streak30, Double(streak), in: context)
    }

    private static func refreshRouteRegular(in context: ModelContext) {
        var descriptor = FetchDescriptor<FrequentRouteAggregate>(
            sortBy: [SortDescriptor(\.count, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let best = (try? context.fetch(descriptor))?.first?.count ?? 0
        setValue(.routesRegular, Double(best), in: context)
    }

    static func currentStreakDays(in context: ModelContext, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let rollups = (try? context.fetch(FetchDescriptor<TripDailyRollup>())) ?? []
        var days = Set<Date>()
        for rollup in rollups where rollup.tripCount > 0 {
            days.insert(calendar.startOfDay(for: rollup.dayStart))
        }
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
            guard days.contains(cursor) else { return 0 }
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private static func setValue(_ id: AchievementID, _ value: Double, in context: ModelContext) {
        let row = progress(for: id, in: context)
        row.currentValue = max(0, value)
        if row.unlockedAt == nil, row.currentValue + 0.000_1 >= id.threshold {
            row.unlockedAt = Date()
        }
    }

    private static func progress(for id: AchievementID, in context: ModelContext) -> AchievementProgress {
        let raw = id.rawValue
        var descriptor = FetchDescriptor<AchievementProgress>(
            predicate: #Predicate { row in
                row.achievementID == raw
            }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = AchievementProgress(achievementID: raw)
        context.insert(created)
        return created
    }

    private static func locality(named name: String, in context: ModelContext) -> VisitedLocality? {
        var descriptor = FetchDescriptor<VisitedLocality>(
            predicate: #Predicate { row in
                row.name == name
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
