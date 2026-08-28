import os
import UIKit
import UserNotifications

/// Handles app-level callbacks that SwiftUI does not expose directly.
///
/// This class receives notification events from iOS, such as the user tapping Snooze
/// or Cancel on a delivered notification.
final class AppNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PillEye", category: "Notifications")

    /// Attaches the notification delegate and registers actions before any reminders fire.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        LocalNotificationScheduler.configureNotificationActions(on: center)
        return true
    }

    /// Restricts the app UI to portrait orientation.
    ///
    /// iOS asks this delegate method which orientations the app supports for each window.
    /// Returning `.portrait` keeps the app fixed upright on iPhone.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }

    /// Controls how notifications appear while the app is already open.
    ///
    /// Without this, iOS may deliver the notification quietly while the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Handles taps on notification actions such as Snooze and Cancel.
    ///
    /// `response.actionIdentifier` tells us which button the user tapped. The original
    /// notification stores the medicine ID in `userInfo`, similar to a small metadata map.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let medicineIDString = userInfo["medicineID"] as? String,
              let medicineID = UUID(uuidString: medicineIDString) else {
            return
        }

        let identifier = LocalNotificationScheduler.identifier(for: medicineID)

        switch response.actionIdentifier {
        case LocalNotificationScheduler.snoozeActionIdentifier:
            // Notifications delivered by older app versions still carry a configured
            // per-medicine snooze in userInfo; honor it once, then the fixed default applies.
            let minutes = userInfo["snoozeMinutes"] as? Int ?? LocalNotificationScheduler.snoozeMinutes
            let content = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent
            guard let content else { return }
            AlarmNotificationSound.applyUrgency(to: content)
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(max(1, minutes) * 60),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                logger.error("Failed to reschedule snoozed reminder.")
            }

        case LocalNotificationScheduler.cancelActionIdentifier, UNNotificationDismissActionIdentifier:
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])

        case UNNotificationDefaultActionIdentifier:
            await MainActor.run {
                MedicineNotificationRoute.postMedicineTapped(medicineID: medicineID)
            }

        default:
            break
        }
    }
}
