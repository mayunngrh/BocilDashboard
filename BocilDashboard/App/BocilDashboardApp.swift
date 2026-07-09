import SwiftUI
import UserNotifications

@main
struct BocilDashboardApp: App {
    @StateObject private var serial        = SerialManager()
    @StateObject private var appearance    = AppearanceManager()
    @StateObject private var language      = AppLanguageManager()
    @StateObject private var calendarStore = CalendarStore()
    @StateObject private var focusStore    = FocusStore()
    @StateObject private var profileService = ProfileBackendService()

    init() { FontLoader.register() }

    var body: some Scene {
        WindowGroup {
            AppView(serial: serial)
                .environmentObject(appearance)
                .environmentObject(language)
                .environmentObject(calendarStore)
                .environmentObject(focusStore)
                .environmentObject(profileService)
                .environment(\.locale, language.locale)
        }
    }
}
