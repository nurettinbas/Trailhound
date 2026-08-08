import Foundation

/// Per–expense-category totals for a day or month (keeps Accessory distinct from Other).
struct VehicleExpenseCategoryAmounts: Sendable, Equatable {
    private(set) var amounts: [VehicleExpenseCategory: Double] = [:]

    var total: Double { amounts.values.reduce(0, +) }

    func amount(for category: VehicleExpenseCategory) -> Double {
        amounts[category, default: 0]
    }

    mutating func add(_ amount: Double, category: VehicleExpenseCategory) {
        amounts[category, default: 0] += amount
    }

    var presentCategories: [VehicleExpenseCategory] {
        VehicleExpenseCategory.allCases.filter { amount(for: $0) > 0 }
    }

    func amount(for bucket: VehicleCostBucket) -> Double {
        VehicleExpenseCategory.allCases
            .filter { $0.costBucket == bucket }
            .reduce(0) { $0 + amount(for: $1) }
    }
}

struct VehicleMonthlyCost: Identifiable, Sendable, Equatable {
    var id: Date { monthStart }
    let monthStart: Date
    let amounts: VehicleExpenseCategoryAmounts

    var total: Double { amounts.total }

    func amount(for category: VehicleExpenseCategory) -> Double {
        amounts.amount(for: category)
    }

    func amount(for bucket: VehicleCostBucket) -> Double {
        amounts.amount(for: bucket)
    }

    init(monthStart: Date, amounts: VehicleExpenseCategoryAmounts) {
        self.monthStart = monthStart
        self.amounts = amounts
    }
}

struct VehicleDailyCost: Identifiable, Sendable, Equatable {
    var id: Date { dayStart }
    let dayStart: Date
    let amounts: VehicleExpenseCategoryAmounts

    var total: Double { amounts.total }

    func amount(for category: VehicleExpenseCategory) -> Double {
        amounts.amount(for: category)
    }

    func amount(for bucket: VehicleCostBucket) -> Double {
        amounts.amount(for: bucket)
    }

    init(dayStart: Date, amounts: VehicleExpenseCategoryAmounts) {
        self.dayStart = dayStart
        self.amounts = amounts
    }
}

struct VehicleCategoryCost: Identifiable, Sendable, Equatable {
    let id: String
    let category: VehicleExpenseCategory?
    let amount: Double
    let isTripEstimate: Bool

    /// Localized in the view layer — never resolve strings inside `@ModelActor` loaders.
    @MainActor
    var displayName: String {
        if isTripEstimate {
            return L10n.string("stats.cost.chart.trip_estimate")
        }
        if let category {
            return category.displayName
        }
        return L10n.string("stats.cost.bucket.other")
    }
}

struct VehicleExpenseShare: Identifiable, Sendable, Equatable {
    let id: String
    /// Empty when unassigned — resolve with L10n in the view.
    let storedName: String
    let amount: Double

    static let unassignedID = VehicleDistance.unassignedID

    @MainActor
    var displayName: String {
        if id == Self.unassignedID || storedName.isEmpty {
            return L10n.string("stats.vehicle.unassigned")
        }
        return storedName
    }
}

struct VehicleCostSnapshot: Sendable, Equatable {
    let months: [VehicleMonthlyCost]
    let days: [VehicleDailyCost]
    let categoryBreakdown: [VehicleCategoryCost]
    let vehicleBreakdown: [VehicleExpenseShare]
    let total: Double
    let fuelTotal: Double
    let serviceTotal: Double
    let insuranceTotal: Double
    let cascoTotal: Double
    let otherTotal: Double

    static let empty = VehicleCostSnapshot(
        months: [],
        days: [],
        categoryBreakdown: [],
        vehicleBreakdown: [],
        total: 0,
        fuelTotal: 0,
        serviceTotal: 0,
        insuranceTotal: 0,
        cascoTotal: 0,
        otherTotal: 0
    )

    var hasData: Bool { total > 0 || !months.isEmpty || !days.isEmpty }
    var hasCategoryBreakdown: Bool { categoryBreakdown.contains { $0.amount > 0 } }
    var hasVehicleBreakdown: Bool { vehicleBreakdown.contains { $0.amount > 0 } }
    var hasTimelineChart: Bool { !days.isEmpty || !months.isEmpty }
}

struct VehicleCostSnapshotRequest: Sendable, Hashable {
    let storeVersion: Int
    let periodStart: Date
    let periodEnd: Date
    let selectedVehicleID: UUID?
}
