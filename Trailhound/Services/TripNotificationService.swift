import Foundation
import SwiftData
import UserNotifications

enum TripNotificationService {
    /// userInfo key carried on notifications that should deep-link somewhere on tap.
    static let actionUserInfoKey = "trailhound.action"
    /// Action value that opens the Pairing tab when the notification is tapped.
    static let openPairingAction = "openPairing"

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    static func notifyTripStarted(tripID: UUID) {
        deliver(
            identifier: "trailhound.trip.started.\(tripID.uuidString)",
            kind: .tripStarted,
            title: L10n.tripStartedTitle,
            body: L10n.tripStartedBody,
            tripID: tripID
        )
    }

    static func notifyTripEnded(
        tripID: UUID,
        distanceMeters: Double,
        duration: TimeInterval,
        routeSummary: String
    ) {
        let km = DateFormatters.formatDistance(distanceMeters)
        let durationText = DateFormatters.formatDuration(duration)
        let format = L10n.string("trip.ended.rich.body")
        let body = String(format: format, km, durationText, routeSummary)
        deliver(
            identifier: "trailhound.trip.ended.\(tripID.uuidString)",
            kind: .tripEnded,
            title: L10n.tripEndedTitle,
            body: body,
            tripID: tripID
        )
    }

    static func notifyTripDiscarded(tripID: UUID) {
        deliver(
            identifier: "trailhound.trip.discarded.\(tripID.uuidString)",
            kind: .tripDiscarded,
            title: L10n.tripDiscardedTitle,
            body: L10n.tripDiscardedBody,
            tripID: tripID
        )
    }

    static func scheduleOrphanStaleNotification(tripID: UUID, lastActivity: Date) {
        let identifier = orphanNotificationID(tripID: tripID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let fireDate = lastActivity.addingTimeInterval(TripRecoveryService.staleThreshold)
        guard fireDate > Date() else {
            notifyOrphanStaleNow(tripID: tripID)
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let title = L10n.string("orphan.stale.title")
            let body = L10n.string("orphan.stale.body")
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["trailhound.inboxRecorded": true]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelOrphanStaleNotification(tripID: UUID) {
        let identifier = orphanNotificationID(tripID: tripID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    static func notifyOrphanStaleNow(tripID: UUID) {
        deliver(
            identifier: orphanNotificationID(tripID: tripID),
            kind: .orphanStale,
            title: L10n.string("orphan.stale.title"),
            body: L10n.string("orphan.stale.body"),
            tripID: tripID
        )
    }

    private static func orphanNotificationID(tripID: UUID) -> String {
        "trailhound.trip.orphan.\(tripID.uuidString)"
    }

    private static func deliver(
        identifier: String,
        kind: AppNotificationKind,
        title: String,
        body: String,
        tripID: UUID? = nil,
        action: String? = nil
    ) {
        Task { @MainActor in
            AppNotificationStore.shared.record(
                kind: kind,
                title: title,
                body: body,
                tripID: tripID
            )
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                #if DEBUG
                print("TripNotificationService: skipped push '\(identifier)' — authorization is \(settings.authorizationStatus.rawValue)")
                #endif
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            var userInfo: [String: Any] = ["trailhound.inboxRecorded": true]
            if let action {
                userInfo[actionUserInfoKey] = action
            }
            content.userInfo = userInfo

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request) { error in
                #if DEBUG
                if let error {
                    print("TripNotificationService: failed to deliver '\(identifier)': \(error.localizedDescription)")
                }
                #endif
            }
        }
    }
}
