import Foundation
import SwiftData
@preconcurrency import UserNotifications

private struct CareReminderPlan: Sendable {
    let vehicleID: UUID
    let vehicleName: String
    let scheduleID: UUID
    let title: String
    let dueDate: Date
    let offsets: [Int]
}

enum VehicleCareNotificationScheduler {
    static let actionUserInfoKey = TripNotificationService.actionUserInfoKey
    static let openVehicleCareAction = "openVehicleCare"
    static let vehicleIDUserInfoKey = "trailhound.vehicleID"
    static let scheduleIDUserInfoKey = "trailhound.scheduleID"

    private static let idPrefix = "trailhound.care."

    static func notificationIdentifier(vehicleID: UUID, scheduleID: UUID, offsetDays: Int) -> String {
        "\(idPrefix)\(vehicleID.uuidString).\(scheduleID.uuidString).\(offsetDays)"
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
                offsets: schedule.reminderOffsetsDays
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

            let calendar = Calendar.current
            let startToday = calendar.startOfDay(for: Date())

            for plan in plans {
                let startDue = calendar.startOfDay(for: plan.dueDate)
                guard startDue >= startToday else { continue }

                for offset in plan.offsets {
                    guard let fireDay = calendar.date(byAdding: .day, value: -offset, to: startDue)
                    else { continue }
                    guard fireDay >= startToday else { continue }

                    var components = calendar.dateComponents([.year, .month, .day], from: fireDay)
                    components.hour = 9
                    components.minute = 0

                    let content = UNMutableNotificationContent()
                    content.title = L10n.string("vehicles.care.notification.title")
                    content.body = String(
                        format: L10n.string("vehicles.care.notification.body"),
                        plan.vehicleName,
                        plan.title,
                        offset
                    )
                    content.sound = .default
                    content.userInfo = [
                        "trailhound.inboxRecorded": true,
                        actionUserInfoKey: openVehicleCareAction,
                        vehicleIDUserInfoKey: plan.vehicleID.uuidString,
                        scheduleIDUserInfoKey: plan.scheduleID.uuidString,
                    ]

                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let request = UNNotificationRequest(
                        identifier: notificationIdentifier(
                            vehicleID: plan.vehicleID,
                            scheduleID: plan.scheduleID,
                            offsetDays: offset
                        ),
                        content: content,
                        trigger: trigger
                    )
                    UNUserNotificationCenter.current().add(request)
                }
            }
        }
    }
}
