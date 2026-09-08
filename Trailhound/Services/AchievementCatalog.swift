import Foundation

enum AchievementID: String, CaseIterable, Sendable {
    case firstTrip = "first.trip"
    case distance100 = "distance.100"
    case distance1000 = "distance.1000"
    case distance10000 = "distance.10000"
    case distance100000 = "distance.100000"
    case business10 = "business.10"
    case business50 = "business.50"
    case streak7 = "streak.7"
    case streak30 = "streak.30"
    case cities10 = "cities.10"
    case cities25 = "cities.25"
    case nightOwl = "night.owl"
    case routesRegular = "routes.regular"

    var threshold: Double {
        switch self {
        case .firstTrip: 1
        case .distance100: 100_000
        case .distance1000: 1_000_000
        case .distance10000: 10_000_000
        case .distance100000: 100_000_000
        case .business10: 10
        case .business50: 50
        case .streak7: 7
        case .streak30: 30
        case .cities10: 10
        case .cities25: 25
        case .nightOwl: 100_000
        case .routesRegular: 10
        }
    }

    var systemImage: String {
        switch self {
        case .firstTrip: "flag.checkered"
        case .distance100, .distance1000, .distance10000, .distance100000: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .business10, .business50: "briefcase.fill"
        case .streak7, .streak30: "flame.fill"
        case .cities10, .cities25: "building.2.fill"
        case .nightOwl: "moon.stars.fill"
        case .routesRegular: "arrow.triangle.swap"
        }
    }

    var titleKey: String { "premium.achievement.\(rawValue).title" }
    var bodyKey: String { "premium.achievement.\(rawValue).body" }

    /// Previous badge in a chain that must unlock before this one is listed as the next target.
    var predecessor: AchievementID? {
        switch self {
        case .distance1000: .distance100
        case .distance10000: .distance1000
        case .distance100000: .distance10000
        case .business50: .business10
        case .streak30: .streak7
        case .cities25: .cities10
        default: nil
        }
    }

    /// Km medals stay in the gallery so the 100 / 1,000 / 10,000 / 100,000 ladder is always visible.
    var listsWhilePredecessorLocked: Bool {
        family == .distance
    }

    var sortOrder: Int {
        switch self {
        case .firstTrip: 0
        case .distance100: 1
        case .distance1000: 2
        case .distance10000: 3
        case .distance100000: 4
        case .business10: 5
        case .business50: 6
        case .streak7: 7
        case .streak30: 8
        case .cities10: 9
        case .cities25: 10
        case .nightOwl: 11
        case .routesRegular: 12
        }
    }

    var family: AchievementFamily {
        switch self {
        case .firstTrip: .firstTrip
        case .distance100, .distance1000, .distance10000, .distance100000: .distance
        case .business10, .business50: .business
        case .streak7, .streak30: .streak
        case .cities10, .cities25: .cities
        case .nightOwl: .night
        case .routesRegular: .routes
        }
    }

    /// 0 = first in family, higher = later milestone (stronger fill).
    var familyTier: Int {
        switch self {
        case .distance1000, .business50, .streak30, .cities25: 1
        case .distance10000: 2
        case .distance100000: 3
        default: 0
        }
    }

    var progressKind: AchievementProgressKind {
        switch self {
        case .distance100, .distance1000, .distance10000, .distance100000, .nightOwl: .distanceMeters
        default: .count
        }
    }

    /// Km medals only. Other families stay enamel (family hue).
    var medalMaterial: AchievementMedalMaterial? {
        switch self {
        case .distance100: .silver
        case .distance1000: .gold
        case .distance10000: .platinum
        case .distance100000: .diamond
        default: nil
        }
    }
}

enum AchievementMedalMaterial: String, Equatable, Sendable {
    case silver
    case gold
    case platinum
    case diamond
}

enum AchievementFamily: String, CaseIterable, Sendable {
    case firstTrip
    case distance
    case business
    case streak
    case cities
    case night
    case routes
}

enum AchievementProgressKind: Sendable {
    case distanceMeters
    case count
}

enum AchievementProgressCaption {
    static func text(for item: AchievementDisplay) -> String {
        text(current: item.currentValue, threshold: item.threshold, kind: item.id.progressKind)
    }

    static func text(current: Double, threshold: Double, kind: AchievementProgressKind) -> String {
        switch kind {
        case .distanceMeters:
            "\(DateFormatters.formatDistance(current)) / \(DateFormatters.formatDistance(threshold))"
        case .count:
            "\(Int(current.rounded())) / \(Int(threshold.rounded()))"
        }
    }
}

struct AchievementDisplay: Identifiable, Equatable, Sendable {
    let id: AchievementID
    let currentValue: Double
    let unlockedAt: Date?
    let needsCelebration: Bool

    var isUnlocked: Bool { unlockedAt != nil }
    var threshold: Double { id.threshold }
    var progress: Double {
        guard threshold > 0 else { return isUnlocked ? 1 : 0 }
        return min(1, currentValue / threshold)
    }

    /// Unlocked first, then catalog order.
    static func listOrder(_ lhs: AchievementDisplay, _ rhs: AchievementDisplay) -> Bool {
        if lhs.isUnlocked != rhs.isUnlocked { return lhs.isUnlocked && !rhs.isUnlocked }
        return lhs.id.sortOrder < rhs.id.sortOrder
    }
}
