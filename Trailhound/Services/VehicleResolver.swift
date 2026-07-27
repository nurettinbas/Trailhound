import Foundation
import SwiftData

enum VehicleResolver {
    @MainActor
    static func resolveActiveVehicle(
        in context: ModelContext,
        settings: AppSettings = .shared
    ) -> VehicleProfile? {
        let vehicles = fetchVehicles(in: context)
        guard !vehicles.isEmpty else { return nil }

        if let preferredID = settings.recordingVehicleID,
           let match = vehicles.first(where: { $0.id == preferredID }) {
            return match
        }

        return vehicles.first(where: \.isDefault) ?? vehicles.first
    }

    static func vehicle(withID id: UUID, in context: ModelContext) -> VehicleProfile? {
        fetchVehicles(in: context).first { $0.id == id }
    }

    static func assign(vehicle: VehicleProfile?, to trip: Trip) {
        trip.vehicleID = vehicle?.id
        trip.vehicle = nil
    }

    private static func fetchVehicles(in context: ModelContext) -> [VehicleProfile] {
        (try? context.fetch(FetchDescriptor<VehicleProfile>())) ?? []
    }
}
