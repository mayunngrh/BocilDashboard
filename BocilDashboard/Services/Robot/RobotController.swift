//
//  RobotController.swift
//  BocilDashboard
//
//  Abstract interface for sending commands to the robot.
//  Implementations can use USB serial, BLE, WiFi, or any transport.
//

import Foundation

protocol RobotController: AnyObject {
    var isConnected: Bool { get }
    func sendCommand(_ command: String)
}
