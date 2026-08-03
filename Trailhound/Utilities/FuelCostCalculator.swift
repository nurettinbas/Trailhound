import Foundation

enum FuelCostCalculator {
    private static let suiteName = "group.com.trailhound.app"
    private static let fuelCurrencyKey = "fuelCurrency"

    static func estimateCost(distanceMeters: Double, vehicle: VehicleProfile? = nil) -> Double {
        let kilometers = distanceMeters / 1000
        guard kilometers > 0 else { return 0 }

        if let vehicle {
            return estimateCost(distanceKilometers: kilometers, vehicle: vehicle)
        }

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let litersPer100 = defaults.double(forKey: "fuelLitersPer100km")
        let pricePerLiter = defaults.double(forKey: "fuelPricePerLiter")
        let consumption = litersPer100 > 0 ? litersPer100 : 7.5
        let price = pricePerLiter > 0 ? pricePerLiter : 65.0
        let liters = kilometers * consumption / 100
        return liters * price
    }

    static func estimateCost(for trip: Trip) -> Double {
        if let cost = trip.estimatedFuelCost, cost > 0 {
            return cost
        }
        return estimateCost(distanceMeters: trip.distanceMeters)
    }

    private static func estimateCost(distanceKilometers: Double, vehicle: VehicleProfile) -> Double {
        let consumption = vehicle.consumption > 0 ? vehicle.consumption : 7.5
        switch vehicle.fuelType {
        case .electric:
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let storedPrice = defaults.double(forKey: "evChargePricePerKWh")
            let price = vehicle.chargePricePerKWh ?? (storedPrice > 0 ? storedPrice : 8.5)
            let kwh = distanceKilometers * consumption / 100
            return kwh * price
        case .petrol, .diesel, .hybrid:
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let pricePerLiter = defaults.double(forKey: "fuelPricePerLiter")
            let price = pricePerLiter > 0 ? pricePerLiter : 65.0
            let liters = distanceKilometers * consumption / 100
            return liters * price
        }
    }

    /// ISO currency code from App Group settings (`TRY` when unset).
    static func resolvedCurrencyCode(
        defaults: UserDefaults? = nil
    ) -> String {
        let store = defaults ?? UserDefaults(suiteName: suiteName) ?? .standard
        if let raw = store.string(forKey: fuelCurrencyKey),
           let currency = FuelCurrency(rawValue: raw) {
            return currency.rawValue
        }
        return FuelCurrency.default.rawValue
    }

    static func formatCost(_ amount: Double, currencyCode: String? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.locale = DateFormatters.currentLocale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode ?? resolvedCurrencyCode()
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    }
}
