//
//  StateBocilPage.swift
//  SimpleBotCil
//
//  Robot control over USB serial — pick a state from the list to send it.
//

import SwiftUI
import ORSSerial

/// One selectable robot state.
struct RobotState: Identifiable {
    let id = UUID()
    let emoji: String
    let label: String
    let command: String
    let color: Color
}

struct StateBocilPage: View {
    @ObservedObject var serial: SerialManager
    @StateObject private var robotController: SerialRobotController

    /// Highlights the last state sent so the user gets feedback.
    @State private var activeCommand: String?

    private let states: [RobotState] = [
        RobotState(emoji: "😊", label: "Happy",   command: "HAPPY",   color: .yellow),
        RobotState(emoji: "😠", label: "Angry",   command: "ANGRY",   color: .red),
        RobotState(emoji: "😪", label: "Sleepy",  command: "SLEEPY",  color: .indigo),
        RobotState(emoji: "😴", label: "Asleep",  command: "ASLEEP",  color: .blue),
        RobotState(emoji: "🎉", label: "Playful", command: "PLAYFUL", color: .orange),
        RobotState(emoji: "⚠️", label: "Alert",   command: "ALERT",   color: .cyan),
        RobotState(emoji: "😐", label: "Idle",    command: "IDLE",    color: .gray),
    ]

    init(serial: SerialManager) {
        self.serial = serial
        _robotController = StateObject(wrappedValue: SerialRobotController(serialManager: serial))
    }

    private var isConnected: Bool {
        robotController.isConnected
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Robot Control")
                .font(.largeTitle)
                .bold()

            // Connection status + port picker
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(isConnected ? "Connected: \(serial.selectedPort?.name ?? "")" : "No robot connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Robot", selection: $serial.selectedPort) {
                    Text("None").tag(Optional<ORSSerialPort>.none)
                    ForEach(serial.availablePorts, id: \.path) { port in
                        Text(port.name).tag(Optional(port))
                    }
                }
                .frame(width: 180)

                Button("Refresh") { serial.refreshPorts() }
            }

            Divider()

            // State list
            List(states) { state in
                Button {
                    robotController.sendCommand(state.command)
                    activeCommand = state.command
                } label: {
                    HStack(spacing: 14) {
                        Text(state.emoji)
                            .font(.title2)
                        Text(state.label)
                            .font(.title3)
                        Spacer()
                        if activeCommand == state.command {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(state.color)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    activeCommand == state.command
                        ? state.color.opacity(0.15)
                        : Color.clear
                )
                .disabled(!isConnected)
            }
            .listStyle(.inset)
            .frame(maxWidth: 420)

            if !isConnected {
                Text("Plug in the robot over USB and pick its port above")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    StateBocilPage(serial: SerialManager())
}
