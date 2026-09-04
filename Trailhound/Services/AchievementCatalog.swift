import Foundation

enum AchievementID: String, CaseIterable, Sendable {
    case firstTrip = "first.trip"
    case distance100 = "distance.100"
    case distance1000 = "distance.1000"
    case distance10000 = "distance.10000"
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
        case .distance100, .distance1000, .distance10000: "point.bottomleft.forward.to.point.topright.scurvepath"
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
        case .business50: .business10
        case .streak30: .streak7
        case .cities25: .cities10
        default: nil
        }
    }

    var sortOrder: Int {
        switch self {
        case .firstTrip: 0
        case .distance100: 1
        case .distance1000: 2
        case .distance10000: 3
        case .business10: 4
        case .business50: 5
        case .streak7: 6
        case .streak30: 7
        case .cities10: 8
        case .cities25: 9
        case .nightOwl: 10
        case .routesRegular: 11
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
}
