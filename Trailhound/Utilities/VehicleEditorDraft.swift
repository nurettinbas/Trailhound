import Foundation
import SwiftData

enum VehiclePhotoEdit: Equatable {
    case unchanged
    case removed
    case newThumb(VehiclePhotoThumb)
}

/// In-memory edits for the pairing vehicle form — persisted only on Save.
struct VehicleEditorDraft: Equatable {
    var name: String
    var fuelType: VehicleFuelType
    var consumption: Double
    var chargePricePerKWh: Double?
    var iconName: String
    var wantsDefault: Bool
    var photoEdit: VehiclePhotoEdit
    /// Existing on-disk photo when the editor opened (for preview / replace / remove).
    var existingPhotoFileName: String?

    init(from vehicle: VehicleProfile) {
        name = vehicle.name
        fuelType = vehicle.fuelType
        consumption = vehicle.consumption
        chargePricePerKWh = vehicle.chargePricePerKWh
        iconName = vehicle.iconName
        wantsDefault = vehicle.isDefault
        photoEdit = .unchanged
        existingPhotoFileName = vehicle.photoFileName
    }

    var consumptionLabel: String {
        fuelType == .electric ? L10n.fuelUnitKWhPer100km : L10n.fuelUnitLPer100km
    }

    var hasDisplayPhoto: Bool {
        switch photoEdit {
        case .removed: return false
        case .newThumb: return true
        case .unchanged: return existingPhotoFileName != nil
        }
    }

    @MainActor
    func apply(
        to vehicle: VehicleProfile,
        allVehicles: [VehicleProfile],
        in context: ModelContext,
        settings: AppSettings,
        photoStore: VehiclePhotoStore = .shared
    ) async throws {
        vehicle.name = name
        vehicle.fuelType = fuelType
        vehicle.consumption = consumption
        vehicle.chargePricePerKWh = chargePricePerKWh
        vehicle.iconName = VehicleIconOption.default.rawValue

        switch photoEdit {
        case .unchanged:
            break
        case .removed:
            if let existing = vehicle.photoFileName {
                photoStore.remove(fileName: existing)
            }
            vehicle.photoFileName = nil
        case .newThumb(let thumb):
            let fileName = try await photoStore.saveThumbnail(
                thumb,
                replacingFileName: vehicle.photoFileName
            )
            vehicle.photoFileName = fileName
        }

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
