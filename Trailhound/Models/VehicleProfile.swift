import Foundation
import SwiftData

@Model
final class VehicleProfile {
    var id: UUID
    var name: String
    var fuelTypeRaw: String
    var consumption: Double
    var chargePricePerKWh: Double?
    var isDefault: Bool
    var iconName: String = VehicleIconOption.default.rawValue
    /// Filename only under Application Support/VehiclePhotos (e.g. `{uuid}.jpg`). Nil = icon fallback.
    var photoFileName: String?

    /// Auto-start binding: when enabled, the paired Bluetooth audio route
    /// (identified by `pairedRouteUID`) triggers connect-start / disconnect-stop.
    var autoStartEnabled: Bool
    var pairedRouteUID: String?
    var pairedRouteName: String?

    /// Optional odometer reading for km-based care schedules (v1.1).
    var currentOdometerKm: Int?

    @Relationship(deleteRule: .nullify, inverse: \Trip.vehicle)
    var trips: [Trip]

    @Relationship(deleteRule: .cascade, inverse: \VehicleSchedule.vehicle)
    var schedules: [VehicleSchedule]

    @Relationship(deleteRule: .cascade, inverse: \VehicleExpense.vehicle)
    var expenses: [VehicleExpense]

    init(
        id: UUID = UUID(),
        name: String,
        fuelType: VehicleFuelType = .petrol,
        consumption: Double = 7.5,
        chargePricePerKWh: Double? = nil,
        isDefault: Bool = false,
        iconName: String = VehicleIconOption.default.rawValue,
        photoFileName: String? = nil,
        autoStartEnabled: Bool = false,
        pairedRouteUID: String? = nil,
        pairedRouteName: String? = nil,
        currentOdometerKm: Int? = nil,
        trips: [Trip] = [],
        schedules: [VehicleSchedule] = [],
        expenses: [VehicleExpense] = []
    ) {
        self.id = id
        self.name = name
        self.fuelTypeRaw = fuelType.rawValue
        self.consumption = consumption
        self.chargePricePerKWh = chargePricePerKWh
        self.isDefault = isDefault
        self.iconName = iconName
        self.photoFileName = photoFileName
        self.autoStartEnabled = autoStartEnabled
        self.pairedRouteUID = pairedRouteUID
        self.pairedRouteName = pairedRouteName
        self.currentOdometerKm = currentOdometerKm
        self.trips = trips
        self.schedules = schedules
        self.expenses = expenses
    }

    var fuelType: VehicleFuelType {
        get { VehicleFuelType(rawValue: fuelTypeRaw) ?? .petrol }
        set { fuelTypeRaw = newValue.rawValue }
    }

    var systemImage: String {
        VehicleIconOption.default.rawValue
    }

    var consumptionLabel: String {
        fuelType == .electric ? L10n.fuelUnitKWhPer100km : L10n.fuelUnitLPer100km
    }
}
