import Foundation
import SwiftData

struct VehicleScheduleEditorDraft: Equatable {
    var kind: VehicleScheduleKind
    var title: String
    var nextDueDate: Date
    var intervalKind: VehicleScheduleIntervalKind
    var intervalMonths: Int
    var intervalKm: Int
    var notes: String
    var isEnabled: Bool

    init(kind: VehicleScheduleKind = .service) {
        self.kind = kind
        self.title = kind.defaultTitle
        self.nextDueDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
        self.intervalKind = kind == .service ? .everyMonths : .everyYears
        self.intervalMonths = kind == .service ? 12 : (kind == .inspection ? 24 : 12)
        self.intervalKm = 15_000
        self.notes = ""
        self.isEnabled = true
    }

    init(from schedule: VehicleSchedule) {
        kind = schedule.kind
        title = schedule.title
        nextDueDate = schedule.nextDueDate ?? Date()
        intervalKind = schedule.intervalKind
        intervalMonths = schedule.intervalMonths ?? 12
        intervalKm = schedule.intervalKm ?? 15_000
        notes = schedule.notes ?? ""
        isEnabled = schedule.isEnabled
    }

    @MainActor
    func apply(to schedule: VehicleSchedule, in context: ModelContext) throws {
        schedule.kind = kind
        schedule.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? kind.defaultTitle
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.nextDueDate = nextDueDate
        schedule.intervalKind = intervalKind
        schedule.intervalMonths = intervalMonths
        schedule.intervalKm = intervalKm
        schedule.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        schedule.isEnabled = isEnabled
        schedule.reminderOffsetsDays = kind.defaultReminderOffsets
        try context.save()
        VehicleCareNotificationScheduler.rescheduleAll(in: context)
    }

    @MainActor
    func insert(for vehicle: VehicleProfile, in context: ModelContext) throws -> VehicleSchedule {
        let schedule = VehicleSchedule(
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            isEnabled: isEnabled,
            nextDueDate: nextDueDate,
            nextDueOdometerKm: intervalKind == .everyKm || intervalKind == .whicheverFirst
                ? (vehicle.currentOdometerKm ?? 0) + intervalKm
                : nil,
            intervalKind: intervalKind,
            intervalMonths: intervalMonths,
            intervalKm: intervalKm,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            vehicle: vehicle
        )
        context.insert(schedule)
        try context.save()
        VehicleCareNotificationScheduler.rescheduleAll(in: context)
        return schedule
    }
}

struct VehicleExpenseEditorDraft: Equatable {
    var category: VehicleExpenseCategory
    var amountText: String
    var occurredAt: Date
    var note: String

    init(category: VehicleExpenseCategory = .fuel) {
        self.category = category
        self.amountText = ""
        self.occurredAt = Date()
        self.note = ""
    }

    init(from expense: VehicleExpense) {
        category = expense.category
        amountText = expense.amount > 0 ? String(Int(expense.amount.rounded())) : ""
        occurredAt = expense.occurredAt
        note = expense.note ?? ""
    }

    /// Whole currency units only (no kuruş / cents). Digits-only text → Int → Double.
    var amount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber), let value = Int(trimmed), value >= 0 else {
            return nil
        }
        return Double(value)
    }

    @MainActor
    func apply(to expense: VehicleExpense, in context: ModelContext) throws {
        guard let amount else { throw VehicleCareError.invalidAmount }
        expense.category = category
        expense.amount = amount.rounded()
        expense.occurredAt = occurredAt
        expense.note = note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        try context.save()
    }

    @MainActor
    func insert(for vehicle: VehicleProfile, in context: ModelContext) throws -> VehicleExpense {
        guard let amount else { throw VehicleCareError.invalidAmount }
        let expense = VehicleExpense(
            category: category,
            amount: amount.rounded(),
            occurredAt: occurredAt,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            source: .manual,
            vehicle: vehicle
        )
        context.insert(expense)
        try context.save()
        return expense
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
