import Foundation

@MainActor
@Observable
final class TabSelection {
    static let shared = TabSelection()

    var selectedTab: AppTab = .trips
    /// Inbox is a root cover, not a page on the Trips stack.
    var showNotificationsCover = false
    /// Bumped when Start should reveal the recording card on Trips.
    private(set) var scrollToRecordingToken = 0
    /// Set by care notification deep link; consumed by PairingTabView.
    private(set) var pendingVehicleCareID: UUID?
    private(set) var pendingStatsAnchor: StatsPremiumAnchor?
    private(set) var pendingTripID: UUID?

    func openPairing() {
        selectedTab = .pairing
    }

    func openTrips() {
        selectedTab = .trips
    }

    func openNotifications() {
        showNotificationsCover = true
    }

    func closeNotifications() {
        showNotificationsCover = false
    }

    /// Switch to Trips and ask the list to show the recording card.
    func focusRecordingCard() {
        openTrips()
        scrollToRecordingToken += 1
    }

    func openVehicleCare(vehicleID: UUID) {
        pendingVehicleCareID = vehicleID
        selectedTab = .pairing
    }

    func consumePendingVehicleCareID() -> UUID? {
        let id = pendingVehicleCareID
        pendingVehicleCareID = nil
        return id
    }

    func openStats(anchor: StatsPremiumAnchor? = nil) {
        pendingStatsAnchor = anchor
        switch anchor {
        case .forecast, .recap, .routes, .achievements:
            selectedTab = .year
        default:
            selectedTab = .stats
        }
    }

    func openTrip(id: UUID) {
        pendingTripID = id
        selectedTab = .trips
    }

    func consumePendingStatsAnchor() -> StatsPremiumAnchor? {
        let value = pendingStatsAnchor
        pendingStatsAnchor = nil
        return value
    }

    func consumePendingTripID() -> UUID? {
        let id = pendingTripID
        pendingTripID = nil
        return id
    }
}

enum StatsPremiumAnchor: String, Hashable {
    case goal
    case forecast
    case recap
    case routes
    case achievements
}

enum AppTab: Hashable {
    case trips
    case stats
    case pairing
    case year
    case settings

    /// Matches `ContentView` TabView order: Trips, Vehicles, Statistics, Recap, Settings.
    var tabBarIndex: Int {
        switch self {
        case .trips: 0
        case .pairing: 1
        case .stats: 2
        case .year: 3
        case .settings: 4
        }
    }
}
