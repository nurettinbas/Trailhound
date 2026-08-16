import Foundation

enum FuelCostCalculator {
    private static let suiteName = "group.com.trailhound.app"
    private static let fuelCurrencyKey = "fuelCurrency"

    /// Resolved L/100 km or kWh/100 km for estimates (trip snapshot → vehicle → global default).
    static func resolvedConsumption(
        tripConsumption: Double? = nil,
        vehicle: VehicleProfile? = nil
    ) -> Double {
        if let tripConsumption, tripConsumption > 0 {
            return tripConsumption
        }
        if let vehicle, vehicle.consumption > 0 {
            return vehicle.consumption
        }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let litersPer100 = defaults.double(forKey: "fuelLitersPer100km")
        return litersPer100 > 0 ? litersPer100 : 7.5
    }

    /// Resolved unit price (per liter or per kWh).
    static func resolvedUnitPrice(
        tripUnitPrice: Double? = nil,
        vehicle: VehicleProfile? = nil
    ) -> Double {
        if let tripUnitPrice, tripUnitPrice > 0 {
            return tripUnitPrice
        }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if vehicle?.fuelType == .electric {
            if let vehiclePrice = vehicle?.chargePricePerKWh, vehiclePrice > 0 {
                return vehiclePrice
            }
            let storedPrice = defaults.double(forKey: "evChargePricePerKWh")
            return storedPrice > 0 ? storedPrice : 8.5
        }
        let pricePerLiter = defaults.double(forKey: "fuelPricePerLiter")
        return pricePerLiter > 0 ? pricePerLiter : 65.0
    }

    static func estimateCost(
        distanceMeters: Double,
        vehicle: VehicleProfile? = nil,
        consumptionPer100: Double? = nil,
        unitPrice: Double? = nil
    ) -> Double {
        let kilometers = distanceMeters / 1000
        guard kilometers > 0 else { return 0 }

        let consumption = resolvedConsumption(tripConsumption: consumptionPer100, vehicle: vehicle)
        let price = resolvedUnitPrice(tripUnitPrice: unitPrice, vehicle: vehicle)
        let volume = kilometers * consumption / 100
        return volume * price
    }

    static func estimateCost(for trip: Trip, vehicle: VehicleProfile? = nil) -> Double {
        if let cost = trip.estimatedFuelCost, cost > 0 {
            return cost
        }
        return estimateCost(
            distanceMeters: trip.distanceMeters,
            vehicle: vehicle,
            consumptionPer100: trip.fuelConsumptionPer100,
            unitPrice: trip.fuelUnitPrice
        )
    }

    /// Applies resolved consumption/price snapshots and recomputes `estimatedFuelCost`.
    static func applyEstimate(
        to trip: Trip,
        distanceMeters: Double,
        vehicle: VehicleProfile?,
        consumptionPer100: Double? = nil,
        unitPrice: Double? = nil
    ) {
        let consumption = resolvedConsumption(
            tripConsumption: (consumptionPer100 ?? 0) > 0 ? consumptionPer100 : trip.fuelConsumptionPer100,
            vehicle: vehicle
        )
        let price = resolvedUnitPrice(
            tripUnitPrice: (unitPrice ?? 0) > 0 ? unitPrice : trip.fuelUnitPrice,
            vehicle: vehicle
        )
        trip.fuelConsumptionPer100 = consumption
        trip.fuelUnitPrice = price
        trip.estimatedFuelCost = estimateCost(
            distanceMeters: distanceMeters,
            vehicle: vehicle,
            consumptionPer100: consumption,
            unitPrice: price
        )
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

    static func formatCost(
        _ amount: Double,
        currencyCode: String? = nil,
        locale: Locale? = nil
    ) -> String {
        let code = currencyCode ?? resolvedCurrencyCode()
        let formatter = NumberFormatter()
        formatter.locale = locale ?? DateFormatters.currentLocale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        if let symbol = FuelCurrency(rawValue: code)?.symbol {
            formatter.currencySymbol = "\(symbol) "
        }
        return formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount.rounded()))"
    }
}
