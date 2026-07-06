//
//  SimpleBotCilApp.swift
//  SimpleBotCil
//
//  Created by Mayun Suryatama on 30/06/26.
//

import SwiftUI
import UserNotifications

@main
struct SimpleBotCilApp: App {
    @StateObject private var serial = SerialManager()
    @StateObject private var googleCalendarService: GoogleCalendarService

    init() {
        FontLoader.register()

        let clientPath = Bundle.main.path(forResource: "google_oauth_client", ofType: "json")!
        let oauth = try! GoogleOAuthManager(clientJSONPath: clientPath)
        _googleCalendarService = StateObject(wrappedValue: GoogleCalendarService(oauth: oauth))
    }

    var body: some Scene {
        WindowGroup {
            AppView(serial: serial)
                .environmentObject(googleCalendarService)
        }
    }
}
