import AppIntents
@preconcurrency import UserNotifications
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        TrailhoundShortcuts.updateAppShortcutParameters()
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
        if !isAlreadyRecordedInInbox(userInfo) {
            let title = notification.request.content.title
            let body = notification.request.content.body
            let identifier = notification.request.identifier
            AppNotificationStore.enqueueSystemNotification(
                title: title,
                body: body,
                identifier: identifier
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
        if !isAlreadyRecordedInInbox(userInfo) {
            let title = response.notification.request.content.title
            let body = response.notification.request.content.body
            let identifier = response.notification.request.identifier
            AppNotificationStore.enqueueSystemNotification(
                title: title,
                body: body,
                identifier: identifier
            )
        } else {
            Task { @MainActor in
                AppNotificationStore.shared.reload()
            }
        }

        if userInfo[TripNotificationService.actionUserInfoKey] as? String == TripNotificationService.openPairingAction {
            Task { @MainActor in
                TabSelection.shared.openPairing()
            }
        } else if userInfo[VehicleCareNotificationScheduler.actionUserInfoKey] as? String
            == VehicleCareNotificationScheduler.openVehicleCareAction {
            let vehicleID = (userInfo[VehicleCareNotificationScheduler.vehicleIDUserInfoKey] as? String)
                .flatMap(UUID.init(uuidString:))
            Task { @MainActor in
                if let vehicleID {
                    TabSelection.shared.openVehicleCare(vehicleID: vehicleID)
                } else {
                    TabSelection.shared.openPairing()
                }
            }
        }
        completionHandler()
    }

    nonisolated private func isAlreadyRecordedInInbox(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["trailhound.inboxRecorded"] as? Bool == true
    }
}
