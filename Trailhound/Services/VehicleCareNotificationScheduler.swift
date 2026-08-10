import Foundation
import SwiftData
@preconcurrency import UserNotifications

private struct CareReminderPlan: Sendable {
    let vehicleID: UUID
    let vehicleName: String
    let scheduleID: UUID
    let title: String
    let dueDate: Date
    let stages: [CareReminderStage]
}

enum VehicleCareNotificationScheduler {
    static let actionUserInfoKey = TripNotificationService.actionUserInfoKey
    static let openVehicleCareAction = "openVehicleCare"
    static let vehicleIDUserInfoKey = "trailhound.vehicleID"
    static let scheduleIDUserInfoKey = "trailhound.scheduleID"
    static let dueDayUserInfoKey = "trailhound.dueDay"
    static let stageUserInfoKey = "trailhound.careStage"

    private static let idPrefix = "trailhound.care."
    private static let overdueDeliveredPrefix = "trailhound.care.overdueDelivered."

    static func notificationIdentifier(
        vehicleID: UUID,
        scheduleID: UUID,
        stage: CareReminderStage
    ) -> String {
        "\(idPrefix)\(vehicleID.uuidString).\(scheduleID.uuidString).\(stage.rawValue)"
    }

    static func cancelAll(for vehicleID: UUID) {
        let prefix = "\(idPrefix)\(vehicleID.uuidString)."
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// Marks a single overdue catch-up as already delivered for this due date (anti-spam).
    static func markOverdueDelivered(scheduleID: UUID, dueDayKey: String) {
        UserDefaults.standard.set(true, forKey: overdueDeliveredKey(scheduleID: scheduleID, dueDayKey: dueDayKey))
    }

    static func markOverdueDeliveredIfNeeded(from userInfo: [AnyHashable: Any]) {
        guard (userInfo[stageUserInfoKey] as? String) == CareReminderStage.overdue.rawValue,
              let scheduleRaw = userInfo[scheduleIDUserInfoKey] as? String,
              let scheduleID = UUID(uuidString: scheduleRaw),
              let dueDayKey = userInfo[dueDayUserInfoKey] as? String,
              !dueDayKey.isEmpty
        else { return }
        markOverdueDelivered(scheduleID: scheduleID, dueDayKey: dueDayKey)
    }

    @MainActor
    static func rescheduleAll(in context: ModelContext) {
        let schedules = (try? context.fetch(FetchDescriptor<VehicleSchedule>())) ?? []
        let plans: [CareReminderPlan] = schedules.compactMap { schedule in
            guard schedule.isEnabled,
                  let dueDate = schedule.nextDueDate,
                  let vehicle = schedule.vehicle else { return nil }
            return CareReminderPlan(
                vehicleID: vehicle.id,
                vehicleName: vehicle.name,
                scheduleID: schedule.id,
                title: schedule.title,
                dueDate: dueDate,
                stages: schedule.kind.reminderStages
            )
        }
        schedule(plans: plans)
    }

    private static func schedule(plans: [CareReminderPlan]) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let careIDs = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            if !careIDs.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: careIDs)
            }
            enqueueReminders(plans: plans)
        }
    }

    private static func enqueueReminders(plans: [CareReminderPlan]) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }

            UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
                let deliveredIDs = Set(delivered.map(\.request.identifier))
                let calendar = Calendar.current
                let today = Date()

                for plan in plans {
                    let entries = CareReminderPlanner.plan(
                        stages: plan.stages,
                        dueDate: plan.dueDate,
                        today: today,
                        calendar: calendar
                    )
                    let dueKey = CareReminderPlanner.dueDayKey(dueDate: plan.dueDate, calendar: calendar)

                    for entry in entries {
                        let identifier = notificationIdentifier(
                            vehicleID: plan.vehicleID,
                            scheduleID: plan.scheduleID,
                            stage: entry.stage
                        )
                        let content = makeContent(plan: plan, stage: entry.stage, dueDayKey: dueKey)

                        switch entry.action {
                        case .schedule(let fireDay):
                            var components = calendar.dateComponents([.year, .month, .day], from: fireDay)
                            components.hour = 9
                            components.minute = 0
                            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                            let request = UNNotificationRequest(
                                identifier: identifier,
                                content: content,
                                trigger: trigger
                            )
                            UNUserNotificationCenter.current().add(request)

                        case .catchUpImmediate:
                            guard entry.stage == .overdue else { continue }
                            guard !hasDeliveredOverdue(
                                scheduleID: plan.scheduleID,
                                dueDayKey: dueKey,
                                identifier: identifier,
                                deliveredIDs: deliveredIDs
                            ) else { continue }
                            markOverdueDelivered(scheduleID: plan.scheduleID, dueDayKey: dueKey)
                            deliverCatchUp(
                                identifier: identifier,
                                content: content
                            )
                        }
                    }
                }
            }
        }
    }

    private static func makeContent(
        plan: CareReminderPlan,
        stage: CareReminderStage,
        dueDayKey: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = L10n.string("vehicles.care.notification.title")
        content.body = body(for: stage, vehicleName: plan.vehicleName, title: plan.title)
        content.sound = .default
        // Omit inboxRecorded so AppDelegate enqueues into the in-app inbox on present/tap.
        content.userInfo = [
            actionUserInfoKey: openVehicleCareAction,
            vehicleIDUserInfoKey: plan.vehicleID.uuidString,
            scheduleIDUserInfoKey: plan.scheduleID.uuidString,
            dueDayUserInfoKey: dueDayKey,
            stageUserInfoKey: stage.rawValue,
        ]
        return content
    }

    private static func body(for stage: CareReminderStage, vehicleName: String, title: String) -> String {
        let key: StaticString
        switch stage {
        case .early: key = "vehicles.care.notification.body.early"
        case .week: key = "vehicles.care.notification.body.week"
        case .dueDay: key = "vehicles.care.notification.body.due_day"
        case .overdue: key = "vehicles.care.notification.body.overdue"
        }
        return String(format: L10n.string(key), vehicleName, title)
    }

    private static func deliverCatchUp(identifier: String, content: UNMutableNotificationContent) {
        // Pre-record so inbox is filled even if the banner is cleared without a tap.
        let title = content.title
        let body = content.body
        var userInfo = content.userInfo
        userInfo["trailhound.inboxRecorded"] = true
        content.userInfo = userInfo
        Task { @MainActor in
            AppNotificationStore.shared.record(
                kind: .vehicleCareReminder,
                title: title,
                body: body
            )
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func hasDeliveredOverdue(
        scheduleID: UUID,
        dueDayKey: String,
        identifier: String,
        deliveredIDs: Set<String>
    ) -> Bool {
        if UserDefaults.standard.bool(forKey: overdueDeliveredKey(scheduleID: scheduleID, dueDayKey: dueDayKey)) {
            return true
        }
        return deliveredIDs.contains(identifier)
    }

    private static func overdueDeliveredKey(scheduleID: UUID, dueDayKey: String) -> String {
        "\(overdueDeliveredPrefix)\(scheduleID.uuidString).\(dueDayKey)"
    }
}
