//
//  ContentView.swift
//  SimpleBotCil
//
//  Created by Mayun Suryatama on 30/06/26.
//

import SwiftUI
import ORSSerial

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var detector = EmotionDetector()
    @StateObject private var posture = PostureDetector()
    @StateObject private var phoneDetector = PhoneDetector()
    @ObservedObject var serial: SerialManager
    @StateObject private var timerMgr = TimerManager()

    private var connectionLabel: String {
        guard let port = serial.selectedPort else { return "No serial port" }
        return "Connected: \(port.name)"
    }

    private var isConnected: Bool {
        serial.selectedPort != nil
    }

    var body: some View {
        VStack(spacing: 16) {

            // MARK: Camera + emotion
            ZStack {
                CameraPreviewView(session: camera.session)
                    .frame(width: 480, height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Skeleton overlay
                SkeletonOverlay(
                    handResults: phoneDetector.lastHandResults,
                    faceObservation: detector.lastFaceObservation,
                    frameSize: CGSize(width: 480, height: 360),
                    bufferSize: camera.bufferSize
                )
                .frame(width: 480, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let message = camera.errorMessage {
                    Text(message)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }

            if detector.faceDetected, let emotion = detector.currentEmotion {
                HStack(spacing: 10) {
                    Text("\(emotion.emoji) \(emotion.rawValue.capitalized)")
                        .font(.title)

                    if let p = posture.currentPosture {
                        Text("·")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.rawValue)
                                .font(.title3)
                            Text(formatDuration(posture.currentDuration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if !posture.isCalibrated {
                        Text("· Calibrating…")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No face detected")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // MARK: Posture accumulated totals
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("🪑 Sitting total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatDuration(posture.totalSittingTime + (posture.currentPosture == .sitting ? posture.currentDuration : 0)))
                        .font(.system(.body, design: .monospaced))
                }
                VStack(spacing: 2) {
                    Text("🧍 Standing total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatDuration(posture.totalStandingTime + (posture.currentPosture == .standing ? posture.currentDuration : 0)))
                        .font(.system(.body, design: .monospaced))
                }
                Spacer()
                Button("Recal") {
                    posture.recalibrate()
                }
                .font(.caption)
            }

            // Debug metrics for posture.
            if detector.faceDetected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "shoulderY: %@  δ: %@  hipL: %.2f  hipR: %.2f",
                                posture.debugShoulderY.map { String(format: "%.3f", $0) } ?? "nil",
                                posture.debugShoulderDelta.map { String(format: "%.3f", $0) } ?? "nil",
                                posture.debugHipL, posture.debugHipR))
                    Text(String(format: "faceH: %@  δ: %@",
                                posture.debugFaceHeight.map { String(format: "%.3f", $0) } ?? "nil",
                                posture.debugFaceDelta.map { String(format: "%.3f", $0) } ?? "nil"))
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            // MARK: Phone detection
            HStack(spacing: 8) {
                Rectangle()
                    .fill(phoneDetector.isPhoneDetected ? .orange : .gray.opacity(0.4))
                    .frame(width: 8, height: 8)
                if phoneDetector.isPhoneDetected {
                    let modeLabel = phoneDetector.detectionMode.map { " (\($0.rawValue))" } ?? ""
                    Text("📱 On phone\(modeLabel) — \(formatDuration(phoneDetector.currentDuration))")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else {
                    Text("📱 Not on phone")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("·")
                    .foregroundStyle(.secondary)
                Text("Total: \(formatDuration(phoneDetector.totalPhoneTime + (phoneDetector.isPhoneDetected ? phoneDetector.currentDuration : 0)))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if detector.faceDetected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "mouthCurvature: %.3f", detector.metrics.mouthCurvature))
                    Text(String(format: "mouthOpenness: %.3f", detector.metrics.mouthOpenness))
                    Text(String(format: "browToEyeGap:   %.3f", detector.metrics.browToEyeGap))
                    Text(String(format: "pitch: %@   handDist: %@   grip: %@   zone: %@",
                                phoneDetector.debugPitch.map { String(format: "%.3f", $0) } ?? "nil",
                                phoneDetector.debugHandDist.map { String(format: "%.3f", $0) } ?? "nil",
                                phoneDetector.debugGrip ? "Y" : "N",
                                phoneDetector.debugInZone ? "Y" : "N"))
                }
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            Divider()

            // MARK: Pomodoro timer
            PomodoroView(timerMgr: timerMgr)

            Divider()

            // MARK: Serial port row
            HStack(spacing: 8) {
                Rectangle()
                    .fill(isConnected ? .green : Bocil.danger)
                    .frame(width: 8, height: 8)
                Text(connectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Port", selection: $serial.selectedPort) {
                    Text("None").tag(Optional<ORSSerialPort>.none)
                    ForEach(serial.availablePorts, id: \.path) { port in
                        Text(port.name).tag(Optional(port))
                    }
                }
                .frame(width: 200)

                Button("Refresh") {
                    serial.refreshPorts()
                }
            }
        }
        .padding()
        .onAppear {
            camera.onFrame = { pixelBuffer in
                detector.process(pixelBuffer: pixelBuffer)
                posture.process(pixelBuffer: pixelBuffer)
                phoneDetector.process(pixelBuffer: pixelBuffer, face: detector.lastFaceObservation)
            }
            camera.start()
            timerMgr.requestNotificationPermission()
        }
        .onDisappear {
            camera.stop()
            serial.disconnect()
        }
        .onChange(of: detector.currentEmotion) { _, newEmotion in
            guard let newEmotion else { return }
            let command = newEmotion.roboEyesCommand
            print("Emotion changed to: \(newEmotion.rawValue) -> Sending command: \(command)")
            serial.send(command: command)
        }
    }
}

// MARK: - Pomodoro subview

private struct PomodoroView: View {
    @ObservedObject var timerMgr: TimerManager

    private let presets: [(label: String, minutes: Int, color: Color)] = [
        ("Focus 15m",  15, .blue),
        ("Focus 25m",  25, .blue),
        ("Break 5m",    5, .green),
        ("Break 10m",  10, .green),
    ]

    var body: some View {
        VStack(spacing: 10) {
            // Preset buttons — always visible
            HStack(spacing: 10) {
                ForEach(presets, id: \.label) { preset in
                    Button(preset.label) {
                        timerMgr.start(seconds: 10, label: preset.label)
                        FloatingTimerWindow.shared.show(timerManager: timerMgr)
                        MenuBarTimer.shared.start(timerManager: timerMgr)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(timerMgr.isRunning && timerMgr.label == preset.label ? .gray : preset.color)
                    .disabled(timerMgr.isRunning && timerMgr.label != preset.label)
                }
            }

            // Stop button shown only while running
            if timerMgr.isRunning {
                Button("Stop Timer (\(timerMgr.remainingFormatted))") {
                    timerMgr.stop()
                    FloatingTimerWindow.shared.close()
                    MenuBarTimer.shared.stop()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(Bocil.danger)
            }
        }
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    if mins > 0 {
        return "\(mins)m \(secs)s"
    } else {
        return "\(secs)s"
    }
}

#Preview {
    ContentView(serial: SerialManager())
}
