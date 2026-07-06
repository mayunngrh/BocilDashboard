//
//  AnyRobotController.swift
//  SimpleBotCil
//
//  Facade that owns whichever RobotController transport is selected in
//  RobotConnectionSettings (USB serial or WiFi), and swaps implementations
//  live if the user changes the setting. Callers depend on this single
//  concrete, observable type instead of switching on RobotController
//  implementations themselves.
//

import Foundation
import Combine

@MainActor
final class AnyRobotController: RobotController, ObservableObject {
    @Published private(set) var isConnected: Bool = false

    private let serial: SerialManager
    private let settings: RobotConnectionSettings
    private var active: RobotController
    private var settingsCancellable: AnyCancellable?
    private var activeCancellable: AnyCancellable?

    init(serial: SerialManager, settings: RobotConnectionSettings) {
        self.serial = serial
        self.settings = settings
        self.active = Self.makeController(mode: settings.mode, serial: serial, host: settings.wifiHost)

        settingsCancellable = settings.$mode
            .combineLatest(settings.$wifiHost)
            .dropFirst()
            .sink { [weak self] mode, host in
                guard let self else { return }
                self.active = Self.makeController(mode: mode, serial: self.serial, host: host)
                self.observeActive()
            }

        observeActive()
    }

    private static func makeController(mode: RobotConnectionMode, serial: SerialManager, host: String) -> RobotController {
        switch mode {
        case .usbSerial:
            return SerialRobotController(serialManager: serial)
        case .wifi:
            return WiFiRobotController(host: host)
        }
    }

    private func observeActive() {
        isConnected = active.isConnected
        if let observable = active as? SerialRobotController {
            activeCancellable = observable.objectWillChange
                .sink { [weak self] _ in
                    guard let self else { return }
                    DispatchQueue.main.async { self.isConnected = self.active.isConnected }
                }
        } else if let observable = active as? WiFiRobotController {
            activeCancellable = observable.$isConnected
                .sink { [weak self] connected in self?.isConnected = connected }
        }
    }

    func sendCommand(_ command: String) {
        active.sendCommand(command)
    }
}
