//
//  SerialManager.swift
//  SimpleBotCil
//

import Foundation
import ORSSerial
import Combine

@MainActor
final class SerialManager: NSObject, ObservableObject {
    @Published var availablePorts: [ORSSerialPort] = []
    @Published var selectedPort: ORSSerialPort? {
        didSet { connect() }
    }
    @Published var isOpen = false

    static let baudRate: NSNumber = 115200

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(portsChanged),
            name: NSNotification.Name.ORSSerialPortsWereConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(portsChanged),
            name: NSNotification.Name.ORSSerialPortsWereDisconnected,
            object: nil
        )
        refreshPorts()
    }

    @objc private func portsChanged() {
        Task { @MainActor in self.refreshPorts() }
    }

    func refreshPorts() {
        availablePorts = ORSSerialPortManager.shared().availablePorts
        print("Available serial ports: \(availablePorts.map { $0.path })")
        if selectedPort == nil {
            selectedPort = availablePorts.first(where: { $0.path.contains("usbserial") || $0.path.contains("usbmodem") })
            if let port = selectedPort {
                print("Auto-selected port: \(port.path)")
            }
        }
    }

    private func connect() {
        guard let port = selectedPort else {
            print("ERROR: No port to connect")
            return
        }
        print("Connecting to \(port.path)...")
        port.baudRate = Self.baudRate
        port.delegate = self
        port.open()
        print("Port open() called")
    }

    func disconnect() {
        selectedPort?.close()
    }

    /// Sends a newline-terminated ASCII command, e.g. "HAPPY\n".
    func send(command: String) {
        guard let port = selectedPort else {
            print("ERROR: No port selected")
            return
        }
        guard let data = (command + "\n").data(using: .ascii) else {
            print("ERROR: Failed to encode command")
            return
        }
        print("Sending: '\(command)' (\(data.count) bytes) to \(port.path)")
        port.send(data)
        // Force a flush to ensure data is sent immediately
        if let fileDescriptor = port.value(forKey: "fileDescriptor") as? Int32 {
            fsync(fileDescriptor)
            print("  -> Data flushed")
        }
    }
}

extension SerialManager: ORSSerialPortDelegate {
    nonisolated func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        Task { @MainActor in self.isOpen = true }
    }

    nonisolated func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        Task { @MainActor in self.isOpen = false }
    }

    nonisolated func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        Task { @MainActor in
            self.isOpen = false
            if self.selectedPort == serialPort {
                self.selectedPort = nil
            }
            self.refreshPorts()
        }
    }

    nonisolated func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {}

    nonisolated func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        Task { @MainActor in self.isOpen = false }
    }
}

