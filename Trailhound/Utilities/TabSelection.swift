import Foundation

@MainActor
@Observable
final class TabSelection {
    static let shared = TabSelection()

    var selectedTab: AppTab = .trips
    /// Set by care notification deep link; consumed by PairingTabView.
    private(set) var pendingVehicleCareID: UUID?

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
}

enum AppTab: Hashable {
    case trips
    case stats
    case pairing
    case settings
    case devLog
}
