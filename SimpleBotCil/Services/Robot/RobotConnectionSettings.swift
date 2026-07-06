//
//  RobotConnectionSettings.swift
//  SimpleBotCil
//
//  Shared, persisted choice of transport (USB serial or WiFi) and the
//  robot's WiFi IP address, used to construct the right RobotController.
//

import Foundation
import Combine

enum RobotConnectionMode: String, CaseIterable {
    case usbSerial
    case wifi

    var label: String {
        switch self {
        case .usbSerial: return "USB Serial"
        case .wifi:      return "WiFi"
        }
    }
}

@MainActor
final class RobotConnectionSettings: ObservableObject {
    private enum Keys {
        static let mode = "robot_connection_mode"
        static let wifiHost = "robot_wifi_host"
    }

    static let defaultPort: UInt16 = 4210

    @Published var mode: RobotConnectionMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) }
    }

    @Published var wifiHost: String {
        didSet { UserDefaults.standard.set(wifiHost, forKey: Keys.wifiHost) }
    }

    init() {
        let storedMode = UserDefaults.standard.string(forKey: Keys.mode).flatMap(RobotConnectionMode.init(rawValue:))
        self.mode = storedMode ?? .usbSerial
        self.wifiHost = UserDefaults.standard.string(forKey: Keys.wifiHost) ?? ""
    }
}
