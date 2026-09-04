import Foundation

@MainActor
@Observable
final class TabSelection {
    static let shared = TabSelection()

    var selectedTab: AppTab = .trips
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
        selectedTab = .stats
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
    case settings
    case devLog
}
