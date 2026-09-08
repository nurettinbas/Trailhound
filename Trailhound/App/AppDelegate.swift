import AppIntents
@preconcurrency import UserNotifications
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if UITestSupport.isEnabled {
            UIView.setAnimationsEnabled(false)
        } else {
            TrailhoundShortcuts.updateAppShortcutParameters()
        }
        Task { @MainActor in
            AppServices.bootstrapRecordingIfNeeded()
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in
            AppServices.bootstrapRecordingIfNeeded()
        }
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        VehicleCareNotificationScheduler.markOverdueDeliveredIfNeeded(from: userInfo)
        RecapNotificationScheduler.markNotifiedIfNeeded(from: userInfo)
        if !isAlreadyRecordedInInbox(userInfo) {
            let title = notification.request.content.title
            let body = notification.request.content.body
            let identifier = notification.request.identifier
            AppNotificationStore.enqueueSystemNotification(
                title: title,
                body: body,
                identifier: identifier,
                userInfo: userInfo
            )
        }
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        VehicleCareNotificationScheduler.markOverdueDeliveredIfNeeded(from: userInfo)
        RecapNotificationScheduler.markNotifiedIfNeeded(from: userInfo)
        if !isAlreadyRecordedInInbox(userInfo) {
            let title = response.notification.request.content.title
            let body = response.notification.request.content.body
            let identifier = response.notification.request.identifier
            AppNotificationStore.enqueueSystemNotification(
                title: title,
                body: body,
                identifier: identifier,
                userInfo: userInfo
            )
        } else {
            Task { @MainActor in
                AppNotificationStore.shared.reload()
            }
        }

        let action = userInfo[TripNotificationService.actionUserInfoKey] as? String
        let tripID = (userInfo[TripNotificationService.tripIDUserInfoKey] as? String)
            .flatMap(UUID.init(uuidString:))
        let target = (userInfo[TripNotificationService.targetUserInfoKey] as? String)
            ?? (userInfo[VehicleCareNotificationScheduler.vehicleIDUserInfoKey] as? String)
        let route = NotificationRoute.resolve(action: action, target: target, tripID: tripID)
        Task { @MainActor in
            route.perform()
        }
        completionHandler()
    }

    nonisolated private func isAlreadyRecordedInInbox(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["trailhound.inboxRecorded"] as? Bool == true
    }
}
