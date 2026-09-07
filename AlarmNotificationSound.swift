import Foundation
import UserNotifications

/// Chooses the sound behavior used by expiry reminders.
///
/// iOS local notifications can only play custom sounds that already exist on the
/// device. For this app, that means an `alarm.caf` file must be bundled with the
/// app target. If that file is missing, the helper falls back to iOS's default
/// notification sound so reminders still make noise.
enum AlarmNotificationSound {
    private static let customSoundResourceName = "alarm"
    private static let customSoundFileName = "alarm.caf"

    /// Returns the custom alarm sound (iOS silently falls back to the default sound if the
    /// file is absent, so no bundle probe is needed).
    static var sound: UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(customSoundFileName))
    }

    /// Marks a notification as time-sensitive so iOS treats it as more urgent.
    ///
    /// This does not bypass the mute switch. Apple only allows that with Critical Alerts,
    /// which require a special entitlement from Apple.
    static func applyUrgency(to content: UNMutableNotificationContent) {
        content.sound = sound
        content.interruptionLevel = .timeSensitive
    }
}
