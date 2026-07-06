//
//  FocusModePage.swift
//  SimpleBotCil
//
//  Focus Mode: detects sitting + phone use, triggers robot commands.
//

import SwiftUI
import ORSSerial

struct FocusModePage: View {
    @StateObject private var viewModel: FocusModeViewModel
    @ObservedObject var serial: SerialManager

    @StateObject private var camera = CameraManager()
    @StateObject private var detector = EmotionDetector()
    @StateObject private var posture = PostureDetector()
    @StateObject private var phoneDetector = PhoneDetector()

    // Thresholds for display
    private let sittingLimit: TimeInterval = 15 * 60   // 15 minutes
    private let phoneLimit: TimeInterval = 10          // 10 seconds

    init(serial: SerialManager) {
        self.serial = serial
        let robotController = SerialRobotController(serialManager: serial)
        let posture = PostureDetector()
        let phoneDetector = PhoneDetector()
        _viewModel = StateObject(wrappedValue: FocusModeViewModel(
            robotController: robotController,
            posture: posture,
            phone: phoneDetector
        ))
        _posture = StateObject(wrappedValue: posture)
        _phoneDetector = StateObject(wrappedValue: phoneDetector)
    }

    var body: some View {
        VStack(spacing: 16) {
            // MARK: Top bar with toggle
            HStack {
                Text("Focus Mode")
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Toggle("", isOn: $viewModel.isFocusModeOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            // MARK: Camera preview (face)
            ZStack {
                if viewModel.isFocusModeOn {
                    CameraPreviewView(session: camera.session)
                        .frame(width: 420, height: 315)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.gray.opacity(0.15))
                        .frame(width: 420, height: 315)
                        .overlay {
                            Text("Focus Mode is off")
                                .foregroundStyle(.secondary)
                        }
                }
            }

            if viewModel.isFocusModeOn {
                // MARK: Live status
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(posture.currentPosture == .sitting ? .orange : .green)
                            .frame(width: 8, height: 8)
                        Text(posture.currentPosture?.rawValue ?? (posture.isCalibrated ? "—" : "Calibrating…"))
                        Spacer()
                        Text(formatDuration(posture.currentDuration))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(posture.currentPosture == .sitting && posture.currentDuration >= sittingLimit ? .red : .primary)
                    }

                    ProgressView(value: min(posture.currentDuration, sittingLimit), total: sittingLimit)
                        .tint(posture.currentDuration >= sittingLimit ? .red : .orange)

                    Divider()

                    HStack(spacing: 8) {
                        Circle()
                            .fill(phoneDetector.isPhoneDetected ? .orange : .gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(phoneDetector.isPhoneDetected ? "On phone" : "Not on phone")
                        Spacer()
                        Text(formatDuration(phoneDetector.currentDuration))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(phoneDetector.currentDuration >= phoneLimit ? .red : .primary)
                    }

                    ProgressView(value: min(phoneDetector.currentDuration, phoneLimit), total: phoneLimit)
                        .tint(phoneDetector.currentDuration >= phoneLimit ? .red : .orange)
                }
                .frame(width: 420)

                HStack(spacing: 8) {
                    Circle()
                        .fill(isRobotConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(isRobotConnected
                         ? "Robot connected (USB): \(serial.selectedPort?.name ?? "")"
                         : "Robot not connected — plug in USB / pick a port in Robot Control tab")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            camera.onFrame = { pixelBuffer in
                detector.process(pixelBuffer: pixelBuffer)
                posture.process(pixelBuffer: pixelBuffer)
                phoneDetector.process(pixelBuffer: pixelBuffer, face: detector.lastFaceObservation)
            }
        }
        .onChange(of: viewModel.isFocusModeOn) { _, isOn in
            if isOn {
                camera.start()
            } else {
                camera.stop()
                posture.recalibrate()
                phoneDetector.reset()
                viewModel.reset()
            }
        }
        .onChange(of: posture.currentDuration) { _, _ in
            viewModel.checkThresholds()
        }
        .onChange(of: phoneDetector.currentDuration) { _, _ in
            viewModel.checkThresholds()
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var isRobotConnected: Bool {
        serial.selectedPort != nil && serial.isOpen
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
    FocusModePage(serial: SerialManager())
}
