//
//  WiFiRobotController.swift
//  BocilDashboard
//
//  RobotController implementation that talks to the ESP32's TCP command
//  server (see ESP32_CozmoMini.ino, port 4210) using the same
//  newline-terminated ASCII command format as USB serial.
//
//  The ESP32 can drop and re-establish WiFi (reboot, brownout, roaming),
//  which kills the TCP socket. This controller detects that and
//  reconnects automatically so sendCommand keeps working without the
//  app needing to be restarted.
//

import Foundation
import Combine
import Network

@MainActor
final class WiFiRobotController: RobotController, ObservableObject {
    @Published private(set) var isConnected: Bool = false

    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.bocil.wifi-robot")
    private var reconnectTask: Task<Void, Never>?
    private var isReady = false

    init(host: String, port: UInt16? = nil) {
        self.host = host
        self.port = port ?? RobotConnectionSettings.defaultPort
        connect()
    }

    deinit {
        reconnectTask?.cancel()
        connection?.cancel()
    }

    private func connect() {
        guard !host.isEmpty, let port = NWEndpoint.Port(rawValue: port) else { return }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        self.connection = connection
        self.isReady = false

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    print("[WiFi] Connected to \(self.host):\(self.port)")
                    self.isReady = true
                    self.isConnected = true
                case .failed(let error):
                    print("[WiFi] Connection failed: \(error) — will reconnect")
                    self.isReady = false
                    self.isConnected = false
                    self.scheduleReconnect()
                case .cancelled:
                    self.isReady = false
                    self.isConnected = false
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            print("[WiFi] Reconnecting to \(self.host)...")
            self.connect()
        }
    }

    func sendCommand(_ command: String) {
        guard let connection, let data = (command + "\n").data(using: .ascii) else { return }
        guard isReady else {
            print("[WiFi] Cannot send '\(command)' — not connected, reconnecting")
            scheduleReconnect()
            return
        }
        print("[WiFi] Sending '\(command)' to \(host):\(port)")
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            print("[WiFi] Send error: \(error)")
            guard let self else { return }
            Task { @MainActor in
                self.isReady = false
                self.isConnected = false
                self.scheduleReconnect()
            }
        })
    }
}
