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

    init() {
        FontLoader.register()
    }

    var body: some Scene {
        WindowGroup {
            AppView(serial: serial)
        }
    }
}
