import SwiftUI
import AVFoundation
import Combine

struct FocusView: View {
    @ObservedObject var serial: SerialManager
    @EnvironmentObject var focusStore: FocusStore

    @StateObject private var camera = CameraManager()
    @StateObject private var detector = EmotionDetector()
    @StateObject private var posture = PostureDetector()
    @StateObject private var phoneDetector = PhoneDetector()
    @StateObject private var robotController: SerialRobotController

    @State private var selectedMinutes: Int? = nil
    @State private var showCustom = false
    @State private var customInput = ""
    @State private var noTimeSelected = false

    @State private var showInfo = false
    @State private var userAllowedCamera = false

    private var cameraActive: Bool {
        userAllowedCamera && camera.isAuthorized
    }

    private var canStart: Bool {
        noTimeSelected || effectiveMinutes != nil
    }

    private var effectiveMinutes: Int? {
        guard !noTimeSelected else { return nil }
        if showCustom, let m = Int(customInput), m > 0 { return m }
        return selectedMinutes
    }

    private var elapsedFormatted: String {
        String(format: "%02d:%02d", focusStore.currentSeconds / 60, focusStore.currentSeconds % 60)
    }

    private let sittingLimit: TimeInterval = 15 * 60
    private let phoneLimit: TimeInterval = 10

    init(serial: SerialManager) {
        self.serial = serial
        let robotController = SerialRobotController(serialManager: serial)
        _robotController = StateObject(wrappedValue: robotController)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            leftPanel
                .frame(width: 190)
                .padding(.top, 32)
                .contentShape(Rectangle())
                .onTapGesture { if showInfo { showInfo = false } }

            rightPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 32)
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear { camera.stop() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            focusStore.tick(effectiveMinutes: effectiveMinutes)
        }
        .onAppear {
            camera.onFrame = { pixelBuffer in
                detector.process(pixelBuffer: pixelBuffer)
                posture.process(pixelBuffer: pixelBuffer)
                phoneDetector.process(pixelBuffer: pixelBuffer, face: detector.lastFaceObservation)
            }
        }
        .onChange(of: focusStore.pendingAutoStart) {
            guard focusStore.pendingAutoStart else { return }
            focusStore.pendingAutoStart = false
            noTimeSelected = true
            selectedMinutes = nil
            showCustom = false
            customInput = ""
            focusStore.start()
        }
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("DEEP WORK")
                .font(Bocil.header(32))
                .foregroundColor(Bocil.ink)

            VStack(alignment: .leading, spacing: 12) {
                Text("SESSION DURATION")
                    .font(Bocil.header(20))
                    .foregroundColor(Bocil.ink)

                VStack(spacing: 6) {
                    ForEach(FocusSession.durations, id: \.self) { min in
                        durationRow(minutes: min)
                    }

                    // Custom time card
                    VStack(spacing: 0) {
                        Button(action: {
                            showCustom = true
                            selectedMinutes = nil
                            noTimeSelected = false
                        }) {
                            HStack(spacing: 12) {
                                Text("Custom time")
                                    .font(Bocil.mono(14))
                                    .foregroundColor(showCustom ? Bocil.onAccent : Bocil.ink)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(showCustom ? Bocil.accentSoft : Bocil.surface)
                            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)

                        if showCustom {
                            HStack(spacing: 8) {
                                TextField("45", text: $customInput)
                                    .textFieldStyle(.plain)
                                    .font(Bocil.mono(14))
                                    .foregroundColor(Bocil.ink)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 50)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                                Text("min")
                                    .font(Bocil.mono(12))
                                    .foregroundColor(Bocil.subtext)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }

                    // No time card
                    Button(action: {
                        noTimeSelected = true
                        selectedMinutes = nil
                        showCustom = false
                        customInput = ""
                    }) {
                        HStack(spacing: 12) {
                            Text("No time")
                                .font(Bocil.mono(14))
                                .foregroundColor(noTimeSelected ? Bocil.onAccent : Bocil.ink)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(noTimeSelected ? Bocil.accentSoft : Bocil.surface)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func durationRow(minutes: Int) -> some View {
        Button(action: {
            selectedMinutes = minutes
            showCustom = false
            customInput = ""
            noTimeSelected = false
        }) {
            HStack(spacing: 12) {
                Text("\(minutes) Minutes")
                    .font(Bocil.mono(14))
                    .foregroundColor(selectedMinutes == minutes && !showCustom && !noTimeSelected ? Bocil.onAccent : Bocil.ink)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(selectedMinutes == minutes && !showCustom && !noTimeSelected ? Bocil.accentSoft : Bocil.surface)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        VStack(spacing: 16) {
            // Camera area
            Group {
                if cameraActive {
                    CameraPreviewView(session: camera.session)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                        .clipShape(Rectangle())
                } else {
                    permissionCard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { if showInfo { showInfo = false } }
            .overlay(alignment: .topTrailing) {
                infoButton
            }
            .overlay(alignment: .topTrailing) {
                if showInfo {
                    infoPopup
                        .padding(.top, 44)
                        .padding(.trailing, 8)
                        .onTapGesture {}
                }
            }

            // Detection status cards
            if cameraActive {
                VStack(spacing: 12) {
                    // Posture card
                    HStack(spacing: 8) {
                        Circle()
                            .fill(posture.currentPosture == .sitting ? .orange : .green)
                            .frame(width: 8, height: 8)
                        Text(posture.currentPosture?.rawValue ?? (posture.isCalibrated ? "—" : "Calibrating…"))
                            .font(Bocil.mono(13))
                            .foregroundColor(Bocil.ink)
                        Spacer()
                        Text(formatDuration(posture.currentDuration))
                            .font(Bocil.mono(12))
                            .foregroundColor(posture.currentPosture == .sitting && posture.currentDuration >= sittingLimit ? .red : Bocil.subtext)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Bocil.surface)
                    .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))

                    // Phone card
                    HStack(spacing: 8) {
                        Circle()
                            .fill(phoneDetector.isPhoneDetected ? .orange : .gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(phoneDetector.isPhoneDetected ? "On phone" : "Not on phone")
                            .font(Bocil.mono(13))
                            .foregroundColor(Bocil.ink)
                        Spacer()
                        Text(formatDuration(phoneDetector.currentDuration))
                            .font(Bocil.mono(12))
                            .foregroundColor(phoneDetector.currentDuration >= phoneLimit ? .red : Bocil.subtext)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Bocil.surface)
                    .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                }
            }

            // Control card
            if cameraActive {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(focusStore.sessionActive ? "DEEP WORK ACTIVE" : "DEEP WORK")
                            .font(Bocil.header(20))
                            .foregroundColor(Bocil.ink)
                        Text(focusStore.sessionActive
                             ? "\(elapsedFormatted) elapsed"
                             : "Mute nudges and let Bocil watch quietly")
                            .font(Bocil.mono(14))
                            .foregroundColor(Bocil.subtext)
                    }
                    Spacer()
                    sessionActionButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(Bocil.surface)
                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
            }
        }
    }

    @ViewBuilder
    private var sessionActionButton: some View {
        if focusStore.sessionActive {
            Button("END SESSION") {
                focusStore.stop()
            }
            .font(Bocil.header(13))
            .foregroundColor(Bocil.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
            .buttonStyle(.plain)
        } else {
            Button("START") {
                guard canStart else { return }
                focusStore.start()
            }
            .font(Bocil.header(13))
            .foregroundColor(Bocil.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(canStart ? Bocil.accentSoft : Bocil.hairline)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Info button

    private var infoButton: some View {
        Button(action: { showInfo.toggle() }) {
            ZStack {
                Rectangle().fill(Bocil.surface)
                Text("i")
                    .font(Bocil.mono(13))
                    .foregroundColor(Bocil.subtext)
            }
            .frame(width: 24, height: 24)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .padding(10)
    }

    // MARK: - Permission card

    private var permissionCard: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Rectangle()
                    .stroke(Bocil.cardBorder, lineWidth: 2)
                    .frame(width: 52, height: 38)
                Circle()
                    .stroke(Bocil.cardBorder, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
            }

            VStack(spacing: 8) {
                Text("CAMERA ACCESS")
                    .font(Bocil.header(20))
                    .foregroundColor(Bocil.ink)
                Text("Helps Bocil understand your presence and support your focus")
                    .font(Bocil.mono(14))
                    .foregroundColor(Bocil.subtext)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button("Not now") {}
                        .font(Bocil.mono(14))
                        .foregroundColor(Bocil.subtext)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                        .buttonStyle(.plain)

                    Button("Allow Camera") {
                        camera.start()
                        userAllowedCamera = true
                    }
                    .font(Bocil.mono(14))
                    .foregroundColor(Bocil.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Bocil.accentSoft)
                    .buttonStyle(.plain)
                }

                if let error = camera.errorMessage {
                    Text(error)
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.danger)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    // MARK: - Info popup

    private var infoPopup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Camera Awareness")
                .font(Bocil.mono(16))
                .foregroundColor(Bocil.ink)

            VStack(alignment: .leading, spacing: 8) {
                ForEach([
                    "Detects your desk presence",
                    "Tracks posture (sitting vs standing)",
                    "Monitors phone use",
                    "No footage is stored",
                    "All processing stays on your Mac"
                ], id: \.self) { point in
                    HStack(alignment: .top, spacing: 10) {
                        Text("·")
                            .font(Bocil.mono(14))
                            .foregroundColor(Bocil.accentSoft)
                        Text(point)
                            .font(Bocil.mono(14))
                            .foregroundColor(Bocil.ink)
                    }
                }
            }
        }
        .padding(20)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.accentSoft, lineWidth: 2))
        .frame(width: 300)
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
    FocusView(serial: SerialManager())
        .environmentObject(FocusStore())
}
