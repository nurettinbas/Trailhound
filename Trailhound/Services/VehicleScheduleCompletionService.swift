import Foundation
import SwiftData

@MainActor
enum VehicleScheduleCompletionService {
    /// Marks a schedule done: creates an expense, rolls the next due date, saves.
    @discardableResult
    static func complete(
        schedule: VehicleSchedule,
        amount: Double,
        occurredAt: Date = Date(),
        odometerKm: Int? = nil,
        note: String? = nil,
        in context: ModelContext,
        rescheduleNotifications: Bool = true
    ) throws -> VehicleExpense {
        guard let vehicle = schedule.vehicle else {
            throw VehicleCareError.missingVehicle
        }

        let expense = VehicleExpense(
            category: .suggested(for: schedule.kind),
            amount: amount,
            occurredAt: occurredAt,
            odometerKm: odometerKm,
            note: note,
            linkedScheduleID: schedule.id,
            source: .manual,
            vehicle: vehicle
        )
        context.insert(expense)

        schedule.lastCompletedAt = occurredAt
        if let odometerKm {
            schedule.lastCompletedOdometerKm = odometerKm
            vehicle.currentOdometerKm = odometerKm
        }

        let next = VehicleCareDueCalculator.nextDueDateAfterCompletion(
            completedOn: occurredAt,
            intervalKind: schedule.intervalKind,
            intervalMonths: schedule.intervalMonths
        )
        schedule.nextDueDate = next

        if schedule.intervalKind == .everyKm || schedule.intervalKind == .whicheverFirst,
           let intervalKm = schedule.intervalKm {
            let base = odometerKm ?? vehicle.currentOdometerKm ?? 0
            schedule.nextDueOdometerKm = base + intervalKm
        }

        try context.save()

        if rescheduleNotifications {
            VehicleCareNotificationScheduler.rescheduleAll(in: context)
        }
        return expense
    }
}

enum VehicleCareError: Error, Equatable {
    case missingVehicle
    case invalidAmount
}
