import SwiftUI
import UserNotifications

@main
struct BocilDashboardApp: App {
    @StateObject private var serial        = SerialManager()
    @StateObject private var appearance    = AppearanceManager()
    @StateObject private var calendarStore = CalendarStore()
    @StateObject private var focusStore    = FocusStore()
    @StateObject private var profileService = ProfileBackendService()

    init() { FontLoader.register() }

    var body: some Scene {
        WindowGroup {
            AppView(serial: serial)
                .environmentObject(appearance)
                .environmentObject(calendarStore)
                .environmentObject(focusStore)
                .environmentObject(profileService)
        }
    }
}
