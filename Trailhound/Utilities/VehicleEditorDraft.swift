import Foundation
import SwiftData

/// In-memory edits for the pairing vehicle form — persisted only on Save.
struct VehicleEditorDraft: Equatable {
    var name: String
    var fuelType: VehicleFuelType
    var consumption: Double
    var chargePricePerKWh: Double?
    var iconName: String
    var wantsDefault: Bool

    init(from vehicle: VehicleProfile) {
        name = vehicle.name
        fuelType = vehicle.fuelType
        consumption = vehicle.consumption
        chargePricePerKWh = vehicle.chargePricePerKWh
        iconName = vehicle.iconName
        wantsDefault = vehicle.isDefault
    }

    var consumptionLabel: String {
        fuelType == .electric ? L10n.fuelUnitKWhPer100km : L10n.fuelUnitLPer100km
    }

    @MainActor
    func apply(
        to vehicle: VehicleProfile,
        allVehicles: [VehicleProfile],
        in context: ModelContext,
        settings: AppSettings
    ) throws {
        vehicle.name = name
        vehicle.fuelType = fuelType
        vehicle.consumption = consumption
        vehicle.chargePricePerKWh = chargePricePerKWh
        vehicle.iconName = iconName

        let others = allVehicles.filter { $0.id != vehicle.id }
        if wantsDefault {
            VehiclePairingService.setDefaultVehicle(vehicle, in: context, save: false)
            settings.recordingVehicleID = vehicle.id
        } else if vehicle.isDefault, let next = others.first {
            VehiclePairingService.setDefaultVehicle(next, in: context, save: false)
        }

        try context.save()
    }
}
