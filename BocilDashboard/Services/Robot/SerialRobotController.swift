//
//  SerialRobotController.swift
//  BocilDashboard
//
//  RobotController implementation using USB serial via SerialManager.
//

import Foundation
import Combine

@MainActor
final class SerialRobotController: RobotController, ObservableObject {
    private let serial: SerialManager

    var isConnected: Bool {
        serial.selectedPort != nil && serial.isOpen
    }

    init(serialManager: SerialManager) {
        self.serial = serialManager
    }

    func sendCommand(_ command: String) {
        guard isConnected else { return }
        serial.send(command: command)
    }
}
