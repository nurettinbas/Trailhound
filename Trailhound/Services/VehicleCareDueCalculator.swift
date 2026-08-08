import Foundation

enum VehicleCareDueCalculator {
    static func dueState(
        nextDueDate: Date?,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> VehicleCareDueState {
        guard let nextDueDate else { return .noDate }
        let startToday = calendar.startOfDay(for: today)
        let startDue = calendar.startOfDay(for: nextDueDate)
        let days = calendar.dateComponents([.day], from: startToday, to: startDue).day ?? 0
        if days > 0 { return .upcoming(daysLeft: days) }
        if days == 0 { return .dueToday }
        return .overdue(days: abs(days))
    }

    static func dueItems(
        from schedules: [VehicleSchedule],
        today: Date = Date(),
        calendar: Calendar = .current,
        urgentOnly: Bool = false
    ) -> [VehicleDueItem] {
        var items: [VehicleDueItem] = []
        for schedule in schedules where schedule.isEnabled {
            guard let vehicle = schedule.vehicle else { continue }
            let state = dueState(nextDueDate: schedule.nextDueDate, today: today, calendar: calendar)
            let item = VehicleDueItem(
                id: schedule.id,
                scheduleID: schedule.id,
                vehicleID: vehicle.id,
                vehicleName: vehicle.name,
                kind: schedule.kind,
                title: schedule.title,
                dueDate: schedule.nextDueDate,
                state: state
            )
            if urgentOnly && !state.isUrgent { continue }
            if case .noDate = state { continue }
            items.append(item)
        }
        return items.sorted { lhs, rhs in
            if lhs.state.sortPriority != rhs.state.sortPriority {
                return lhs.state.sortPriority < rhs.state.sortPriority
            }
            return lhs.daysSortKey < rhs.daysSortKey
        }
    }

    /// Urgent service schedule for a single vehicle (recording-card badge).
    static func urgentServiceDue(
        for vehicleID: UUID,
        from schedules: [VehicleSchedule],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> VehicleDueItem? {
        dueItems(from: schedules, today: today, calendar: calendar, urgentOnly: true)
            .first { $0.vehicleID == vehicleID && $0.kind == .service }
    }

    /// Advances `nextDueDate` after a completion, using the schedule interval.
    static func nextDueDateAfterCompletion(
        completedOn: Date,
        intervalKind: VehicleScheduleIntervalKind,
        intervalMonths: Int?,
        calendar: Calendar = .current
    ) -> Date? {
        switch intervalKind {
        case .none, .everyKm:
            return nil
        case .everyMonths:
            let months = max(1, intervalMonths ?? 12)
            return calendar.date(byAdding: .month, value: months, to: completedOn)
        case .everyYears:
            let years = max(1, (intervalMonths ?? 12) / 12)
            let monthCount = intervalMonths ?? (years * 12)
            if monthCount % 12 == 0 {
                return calendar.date(byAdding: .year, value: monthCount / 12, to: completedOn)
            }
            return calendar.date(byAdding: .month, value: monthCount, to: completedOn)
        case .whicheverFirst:
            let months = max(1, intervalMonths ?? 12)
            return calendar.date(byAdding: .month, value: months, to: completedOn)
        }
    }

    static func subtitle(for state: VehicleCareDueState, title: String) -> String {
        switch state {
        case .upcoming(let days):
            return String(format: L10n.string("vehicles.care.due.days_left"), title, days)
        case .dueToday:
            return String(format: L10n.string("vehicles.care.due.today"), title)
        case .overdue(let days):
            return String(format: L10n.string("vehicles.care.due.overdue"), title, days)
        case .noDate:
            return title
        }
    }

    static func shortSubtitle(for state: VehicleCareDueState) -> String? {
        switch state {
        case .upcoming(let days):
            return String(format: L10n.string("vehicles.care.due.short_days"), days)
        case .dueToday:
            return L10n.string("vehicles.care.due.short_today")
        case .overdue(let days):
            return String(format: L10n.string("vehicles.care.due.short_overdue"), days)
        case .noDate:
            return nil
        }
    }
}
