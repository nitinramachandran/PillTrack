import SwiftUI

/// The app entry point.
@main
struct Medicine_Date_AlerterApp: App {
    /// SwiftUI apps don't have an app delegate by default; this adapter wires one in
    /// so notification callbacks (snooze, cancel, tap-to-open) can be handled.
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var notificationDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
