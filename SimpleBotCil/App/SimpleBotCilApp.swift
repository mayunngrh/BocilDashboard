import SwiftUI
import UserNotifications

@main
struct SimpleBotCilApp: App {
    @StateObject private var serial        = SerialManager()
    @StateObject private var appearance    = AppearanceManager()
    @StateObject private var calendarStore = CalendarStore()
    @StateObject private var focusStore    = FocusStore()

    init() { FontLoader.register() }

    var body: some Scene {
        WindowGroup {
            AppView(serial: serial)
                .environmentObject(appearance)
                .environmentObject(calendarStore)
                .environmentObject(focusStore)
        }
    }
}
