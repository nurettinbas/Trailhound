import Foundation

enum RecapStoryPage: Int, CaseIterable, Hashable, Sendable {
    case intro
    case distance
    case cities
    case route
    case time
    case categories
    case cost
    case badges
    case closing
}

enum RecapStoryPagePolicy {
    static func pages(for snapshot: YearRecapSnapshot) -> [RecapStoryPage] {
        RecapStoryPage.allCases.filter { page in
            switch page {
            case .cities:
                snapshot.cityCount > 0
            case .time:
                snapshot.longestStreak > 0
                    || snapshot.busiestMonth != nil
                    || snapshot.nightDistanceMeters > 0
            case .categories:
                snapshot.businessDistanceMeters > 0 || snapshot.otherDistanceMeters > 0
            case .route:
                snapshot.topRouteCount >= 2
            case .cost:
                snapshot.estimatedFuelCost > 0 || snapshot.paidExpenses > 0
            case .badges:
                snapshot.unlockedAchievementIDs.contains { AchievementID(rawValue: $0) != nil }
            case .intro, .distance, .closing:
                true
            }
        }
    }
}
