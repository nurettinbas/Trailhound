import Foundation

enum TripCategory: String, Codable, CaseIterable {
    case personal
    case business

    var displayName: String {
        switch self {
        case .personal: L10n.categoryPersonal
        case .business: L10n.categoryBusiness
        }
    }
}

enum GeocodeStatus: String, Codable {
    case pending
    case complete
    case failed
}

enum SavedPlaceKind: String, Codable, CaseIterable {
    case home
    case work
    case other

    var displayName: String {
        switch self {
        case .home: L10n.placeHome
        case .work: L10n.placeWork
        case .other: L10n.placeOther
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .work: "building.2.fill"
        case .other: "mappin.circle.fill"
        }
    }
}

enum VehicleFuelType: String, Codable, CaseIterable {
    case petrol
    case diesel
    case electric
    case hybrid

    var displayName: String {
        switch self {
        case .petrol: L10n.fuelPetrol
        case .diesel: L10n.fuelDiesel
        case .electric: L10n.fuelElectric
        case .hybrid: L10n.fuelHybrid
        }
    }
}

enum VehicleIconOption: String, CaseIterable, Identifiable {
    case car = "car.fill"
    case carSide = "car.side.fill"
    case carRear = "car.rear.fill"
    case carFrontWaves = "car.front.waves.up.fill"
    case carCircle = "car.circle.fill"
    case cars = "car.2.fill"
    case electric = "bolt.car.fill"
    case suv = "suv.side.fill"
    case convertible = "convertible.side.fill"
    case pickup = "truck.pickup.side.fill"
    case truck = "truck.box.fill"
    case bus = "bus.fill"
    case doubleDecker = "bus.doubledecker.fill"
    case tram = "tram.fill"
    case cableCar = "cablecar.fill"
    case scooter = "scooter"
    case bicycle = "bicycle"
    case bicycleCircle = "bicycle.circle.fill"
    case mopedOutline = "moped"
    case moped = "moped.fill"
    case motorcycleOutline = "motorcycle"
    case motorcycle = "motorcycle.fill"

    var id: String { rawValue }

    static let `default`: VehicleIconOption = .car

    static var available: [VehicleIconOption] {
        allCases.filter(\.isAvailable)
    }

    /// Curated icons for add/edit vehicle (cars, motorcycles, moped/Vespa).
    static var pairingEditorIcons: [VehicleIconOption] {
        let candidates: [VehicleIconOption] = [
            .car,
            .electric,
            .suv,
            .convertible,
            .pickup,
            .truck,
            .moped,
            .motorcycle
        ]
        var seen = Set<String>()
        return candidates.filter { option in
            guard option.isAvailable else { return false }
            return seen.insert(option.rawValue).inserted
        }
    }

    var isAvailable: Bool {
        switch self {
        case .convertible, .moped, .mopedOutline, .motorcycle, .motorcycleOutline:
            if #available(iOS 18.0, *) { return true }
            return false
        default:
            return true
        }
    }

    static func resolved(_ iconName: String?) -> VehicleIconOption {
        guard let iconName else { return .default }
        if let option = VehicleIconOption(rawValue: iconName), option.isAvailable {
            return option
        }
        // Legacy raw values from earlier builds.
        switch iconName {
        case "motorcycle":
            return resolved(Self.motorcycle.rawValue)
        case "moped":
            return resolved(Self.moped.rawValue)
        case "fuelpump.fill", "airplane", "ferry.fill", "car.ferry.fill", "sailboat.fill":
            return .default
        default:
            return .default
        }
    }

}

enum TripLabelOption: String, CaseIterable {
    case work = "İş"
    case market = "Market"
    case holiday = "Tatil"
    case other = "Diğer"

    var displayName: String {
        switch self {
        case .work: L10n.labelWork
        case .market: L10n.labelMarket
        case .holiday: L10n.labelHoliday
        case .other: L10n.labelOther
        }
    }
}
