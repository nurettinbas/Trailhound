import Foundation
import SwiftData

@Model
final class VehicleExpense {
    var id: UUID
    var categoryRaw: String
    var amount: Double
    var occurredAt: Date
    var odometerKm: Int?
    var vendor: String?
    var note: String?
    var linkedScheduleID: UUID?
    var sourceRaw: String

    var vehicle: VehicleProfile?

    init(
        id: UUID = UUID(),
        category: VehicleExpenseCategory,
        amount: Double,
        occurredAt: Date = Date(),
        odometerKm: Int? = nil,
        vendor: String? = nil,
        note: String? = nil,
        linkedScheduleID: UUID? = nil,
        source: VehicleExpenseSource = .manual,
        vehicle: VehicleProfile? = nil
    ) {
        self.id = id
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.occurredAt = occurredAt
        self.odometerKm = odometerKm
        self.vendor = vendor
        self.note = note
        self.linkedScheduleID = linkedScheduleID
        self.sourceRaw = source.rawValue
        self.vehicle = vehicle
    }

    var category: VehicleExpenseCategory {
        get { VehicleExpenseCategory.resolved(fromRaw: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    var source: VehicleExpenseSource {
        get { VehicleExpenseSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
