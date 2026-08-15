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

    /// - Returns: `true` when the rich system banner was posted immediately (start place already known).
    @discardableResult
    static func notifyTripStarted(tripID: UUID, startSummary: String) -> Bool {
        let body = startedBody(startSummary: startSummary)
        let identifier = startedNotificationID(tripID: tripID)
        // Always land in the inbox immediately.
        Task { @MainActor in
            AppNotificationStore.shared.record(
                kind: .tripStarted,
                title: L10n.tripStartedTitle,
                body: body,
                tripID: tripID
            )
        }
        // Prefer posting the system banner once we know "From …". If place is already
        // known, post now; otherwise wait briefly for the first GPS/place refresh.
        if body != L10n.tripStartedBody {
            postSystemNotification(
                identifier: identifier,
                title: L10n.tripStartedTitle,
                body: body
            )
            return true
        }
        scheduleDeferredStartedPush(tripID: tripID)
        return false
    }

    /// Updates the inbox trip-started row when start place becomes available (first fix / trip end).
    /// - Parameter postBanner: When true, posts/replaces the system banner so it matches inbox
    ///   (used while recording). Pass false at trip end so we don't re-alert "Trip started".
    @MainActor
    static func refreshTripStartedBody(tripID: UUID, startSummary: String, postBanner: Bool = true) {
        let body = startedBody(startSummary: startSummary)
        guard body != L10n.tripStartedBody else { return }
        let bodyChanged = AppNotificationStore.shared.updateTripStartedBody(tripID: tripID, body: body)
        cancelDeferredStartedPush(tripID: tripID)
        // Same body as notifyTripStarted (or inbox row not written yet) — don't re-alert.
        guard postBanner, bodyChanged else { return }
        postSystemNotification(
            identifier: startedNotificationID(tripID: tripID),
            title: L10n.tripStartedTitle,
            body: body
        )
    }

    private static func startedBody(startSummary: String) -> String {
        if startSummary.isEmpty || startSummary == "—" {
            return L10n.tripStartedBody
        }
        return String(format: L10n.string("trip.started.rich.body"), startSummary)
    }

    private static func startedNotificationID(tripID: UUID) -> String {
        "trailhound.trip.started.\(tripID.uuidString)"
    }

    private static func deferredStartedPushID(tripID: UUID) -> String {
        "trailhound.trip.started.deferred.\(tripID.uuidString)"
    }

    /// Fallback: if place never resolves, still show the generic started banner after a short wait.
    private static func scheduleDeferredStartedPush(tripID: UUID) {
        let identifier = deferredStartedPushID(tripID: tripID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = L10n.tripStartedTitle
        content.body = L10n.tripStartedBody
        content.sound = .default
        content.userInfo = ["trailhound.inboxRecorded": true]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2.5, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelDeferredStartedPush(tripID: UUID) {
        let identifier = deferredStartedPushID(tripID: tripID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private static func postSystemNotification(identifier: String, title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["trailhound.inboxRecorded": true]
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
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

    static func notifyTripsMerged(tripID: UUID, legCount: Int) {
        deliver(
            identifier: "trailhound.trip.merged.\(tripID.uuidString)",
            kind: .tripsMerged,
            title: L10n.tripsMergedTitle,
            body: L10n.tripsMergedBody(legCount),
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
