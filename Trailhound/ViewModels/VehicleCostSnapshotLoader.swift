import Foundation
import SwiftData

/// Aggregates recorded vehicle expenses for Stats, off the main actor.
/// Trip estimated fuel stays in trip summary / daily fuel charts — not mixed into expense bars.
@ModelActor
actor VehicleCostSnapshotLoader {
    private static let maxCacheEntries = 8

    private var cache: [VehicleCostSnapshotRequest: VehicleCostSnapshot] = [:]
    private var cacheOrder: [VehicleCostSnapshotRequest] = []
    private var cachedStoreVersion: Int?

    func snapshot(for request: VehicleCostSnapshotRequest) -> VehicleCostSnapshot {
        if cachedStoreVersion != request.storeVersion {
            cache.removeAll(keepingCapacity: true)
            cacheOrder.removeAll(keepingCapacity: true)
            cachedStoreVersion = request.storeVersion
        }
        if let cached = cache[request] { return cached }
        let built = build(request)
        insertCache(request, snapshot: built)
        return built
    }

    func clearCache() {
        cache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
        cachedStoreVersion = nil
    }

    private func insertCache(_ request: VehicleCostSnapshotRequest, snapshot: VehicleCostSnapshot) {
        if cache[request] == nil {
            cacheOrder.append(request)
        }
        cache[request] = snapshot
        while cacheOrder.count > Self.maxCacheEntries {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    private func build(_ request: VehicleCostSnapshotRequest) -> VehicleCostSnapshot {
        let calendar = Calendar.current
        let lowerBound = request.periodStart
        let upperBound = request.periodEnd

        var monthBuckets: [Date: VehicleExpenseCategoryAmounts] = [:]
        var dayBuckets: [Date: VehicleExpenseCategoryAmounts] = [:]
        var categoryTotals: [VehicleExpenseCategory: Double] = [:]
        var vehicleTotals: [String: (name: String, amount: Double)] = [:]

        let expenses = fetchExpenses(
            from: lowerBound,
            to: upperBound,
            vehicleID: request.selectedVehicleID
        )
        for expense in expenses {
            let month = calendar.date(
                from: calendar.dateComponents([.year, .month], from: expense.occurredAt)
            ) ?? expense.occurredAt
            let day = calendar.startOfDay(for: expense.occurredAt)
            let category = expense.category

            var monthBucket = monthBuckets[month] ?? VehicleExpenseCategoryAmounts()
            monthBucket.add(expense.amount, category: category)
            monthBuckets[month] = monthBucket

            var dayBucket = dayBuckets[day] ?? VehicleExpenseCategoryAmounts()
            dayBucket.add(expense.amount, category: category)
            dayBuckets[day] = dayBucket

            categoryTotals[category, default: 0] += expense.amount

            let vehicleKey = expense.vehicle?.id.uuidString ?? VehicleExpenseShare.unassignedID
            let vehicleName = expense.vehicle?.name ?? ""
            let existing = vehicleTotals[vehicleKey]
            vehicleTotals[vehicleKey] = (
                name: existing?.name.isEmpty == false ? existing!.name : vehicleName,
                amount: (existing?.amount ?? 0) + expense.amount
            )
        }

        let months = monthBuckets.keys.sorted().map {
            VehicleMonthlyCost(monthStart: $0, amounts: monthBuckets[$0]!)
        }
        let days = dayBuckets.keys.sorted().map {
            VehicleDailyCost(dayStart: $0, amounts: dayBuckets[$0]!)
        }

        let categoryBreakdown: [VehicleCategoryCost] = VehicleExpenseCategory.allCases.compactMap { category in
            let amount = categoryTotals[category, default: 0]
            guard amount > 0 else { return nil }
            return VehicleCategoryCost(
                id: category.rawValue,
                category: category,
                amount: amount,
                isTripEstimate: false
            )
        }
        .sorted { lhs, rhs in
            if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }

        let vehicleBreakdown: [VehicleExpenseShare] = vehicleTotals
            .map { key, value in
                VehicleExpenseShare(id: key, storedName: value.name, amount: value.amount)
            }
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }

        return VehicleCostSnapshot(
            months: months,
            days: days,
            categoryBreakdown: categoryBreakdown,
            vehicleBreakdown: vehicleBreakdown,
            total: months.reduce(0) { $0 + $1.total },
            fuelTotal: months.reduce(0) { $0 + $1.amount(for: VehicleCostBucket.fuel) },
            serviceTotal: months.reduce(0) { $0 + $1.amount(for: VehicleCostBucket.service) },
            insuranceTotal: months.reduce(0) { $0 + $1.amount(for: VehicleCostBucket.insurance) },
            cascoTotal: months.reduce(0) { $0 + $1.amount(for: VehicleCostBucket.casco) },
            otherTotal: months.reduce(0) { $0 + $1.amount(for: VehicleCostBucket.other) }
        )
    }

    private func fetchExpenses(from: Date, to: Date, vehicleID: UUID?) -> [VehicleExpense] {
        let descriptor = FetchDescriptor<VehicleExpense>(
            predicate: #Predicate { expense in
                expense.occurredAt >= from && expense.occurredAt <= to
            },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        let all = (try? modelContext.fetch(descriptor)) ?? []
        guard let vehicleID else { return all }
        return all.filter { $0.vehicle?.id == vehicleID }
    }
}
