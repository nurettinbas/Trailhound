import Foundation
import SwiftData

enum AchievementEvaluator {
    @discardableResult
    static func apply(
        trip: Trip,
        sign: Double,
        localities: [String],
        in context: ModelContext,
        notify: Bool = true
    ) -> [AchievementID] {
        guard trip.endedAt != nil else { return [] }
        var newly: [AchievementID] = []
        func collect(_ id: AchievementID, unlocked: Bool) {
            if unlocked { newly.append(id) }
        }
        collect(.firstTrip, unlocked: bump(.firstTrip, by: sign, in: context))
        collect(.distance100, unlocked: bump(.distance100, by: sign * trip.distanceMeters, in: context))
        collect(.distance1000, unlocked: bump(.distance1000, by: sign * trip.distanceMeters, in: context))
        collect(.distance10000, unlocked: bump(.distance10000, by: sign * trip.distanceMeters, in: context))
        collect(.distance100000, unlocked: bump(.distance100000, by: sign * trip.distanceMeters, in: context))
        seedDistance100000(in: context)
        if trip.categoryID == BuiltInCategory.businessID.uuidString {
            collect(.business10, unlocked: bump(.business10, by: sign, in: context))
            collect(.business50, unlocked: bump(.business50, by: sign, in: context))
        }
        collect(.nightOwl, unlocked: bump(.nightOwl, by: sign * (trip.nightDistanceMeters ?? 0), in: context))
        newly.append(contentsOf: applyLocalities(localities, sign: sign, in: context))
        newly.append(contentsOf: refreshStreak(in: context))
        newly.append(contentsOf: refreshRouteRegular(in: context))
        if notify, sign > 0, !newly.isEmpty, !UITestSupport.isUnitTesting {
            let ids = newly
            Task { @MainActor in
                TripNotificationService.notifyAchievementsUnlocked(ids)
            }
        }
        return newly
    }

    static func displays(in context: ModelContext) -> [AchievementDisplay] {
        seedDistance100000(in: context)
        let rows = (try? context.fetch(FetchDescriptor<AchievementProgress>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.achievementID, $0) })
        let unlocked = Set(rows.compactMap { row -> AchievementID? in
            guard row.unlockedAt != nil else { return nil }
            return AchievementID(rawValue: row.achievementID)
        })
        return AchievementID.allCases.compactMap { id in
            if let predecessor = id.predecessor,
               !id.listsWhilePredecessorLocked,
               !unlocked.contains(predecessor),
               byID[id.rawValue]?.unlockedAt == nil {
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
        .sorted(by: AchievementDisplay.listOrder)
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
            apply(
                trip: trip,
                sign: 1,
                localities: TripLocalityResolver.localities(on: trip),
                in: context,
                notify: false
            )
        }
    }

    /// Copy cumulative metres onto the 100,000 km row without a full rebuild.
    /// Already-earned unlocks skip the celebration overlay (`seenAt = now`).
    private static func seedDistance100000(in context: ModelContext) {
        let meters = [
            storedValue(for: .distance100, in: context),
            storedValue(for: .distance1000, in: context),
            storedValue(for: .distance10000, in: context)
        ].max() ?? 0
        guard meters > 0 else { return }
        let row = progress(for: .distance100000, in: context)
        if row.currentValue + 0.000_1 < meters {
            row.currentValue = meters
        }
        if row.unlockedAt == nil, row.currentValue + 0.000_1 >= AchievementID.distance100000.threshold {
            let now = Date()
            row.unlockedAt = now
            row.seenAt = now
            YearRecapCache.invalidate(yearContaining: now)
        }
    }

    private static func storedValue(for id: AchievementID, in context: ModelContext) -> Double {
        let raw = id.rawValue
        var descriptor = FetchDescriptor<AchievementProgress>(
            predicate: #Predicate { row in
                row.achievementID == raw
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.currentValue ?? 0
    }

    @discardableResult
    private static func bump(_ id: AchievementID, by delta: Double, in context: ModelContext) -> Bool {
        guard delta != 0 else { return false }
        let row = progress(for: id, in: context)
        row.currentValue = max(0, row.currentValue + delta)
        if row.unlockedAt == nil, row.currentValue + 0.000_1 >= id.threshold {
            row.unlockedAt = Date()
            YearRecapCache.invalidate(yearContaining: row.unlockedAt ?? Date())
            return true
        }
        return false
    }

    @discardableResult
    private static func applyLocalities(_ localities: [String], sign: Double, in context: ModelContext) -> [AchievementID] {
        guard sign != 0 else { return [] }
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
        var newly: [AchievementID] = []
        if setValue(.cities10, count, in: context) { newly.append(.cities10) }
        if setValue(.cities25, count, in: context) { newly.append(.cities25) }
        return newly
    }

    @discardableResult
    private static func refreshStreak(in context: ModelContext) -> [AchievementID] {
        let streak = currentStreakDays(in: context)
        var newly: [AchievementID] = []
        if setValue(.streak7, Double(streak), in: context) { newly.append(.streak7) }
        if setValue(.streak30, Double(streak), in: context) { newly.append(.streak30) }
        return newly
    }

    @discardableResult
    private static func refreshRouteRegular(in context: ModelContext) -> [AchievementID] {
        var descriptor = FetchDescriptor<FrequentRouteAggregate>(
            sortBy: [SortDescriptor(\.count, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let best = (try? context.fetch(descriptor))?.first?.count ?? 0
        if setValue(.routesRegular, Double(best), in: context) {
            return [.routesRegular]
        }
        return []
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

    @discardableResult
    private static func setValue(_ id: AchievementID, _ value: Double, in context: ModelContext) -> Bool {
        let row = progress(for: id, in: context)
        row.currentValue = max(0, value)
        if row.unlockedAt == nil, row.currentValue + 0.000_1 >= id.threshold {
            row.unlockedAt = Date()
            YearRecapCache.invalidate(yearContaining: row.unlockedAt ?? Date())
            return true
        }
        return false
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

/// Stats unlock overlay queue. Append newly unlocked badges; never reset the card on screen.
enum AchievementUnlockQueue {
    static func merging(queued: [AchievementDisplay], pending: [AchievementDisplay]) -> [AchievementDisplay] {
        if queued.isEmpty { return pending }
        let ids = Set(queued.map(\.id))
        return queued + pending.filter { !ids.contains($0.id) }
    }
}

/// Compact Stats strip: unlocked medals only. Locked progress lives in the gallery.
enum AchievementStripPreview {
    static let unlockedCap = 8

    static func medals(from achievements: [AchievementDisplay]) -> [AchievementDisplay] {
        Array(achievements.filter(\.isUnlocked).prefix(unlockedCap))
    }
}
