import SwiftUI
import AVFoundation
import Combine

// Publishes the timer button's bounds so the dropdown can be rendered by a
// top-level container (above the control card's own border, which would
// otherwise paint over an inner overlay).
private struct TimerAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct FocusView: View {
    @ObservedObject var serial: SerialManager
    @EnvironmentObject var focusStore: FocusStore

    @StateObject private var camera = CameraManager()
    @StateObject private var detector = EmotionDetector()
    @StateObject private var posture = PostureDetector()
    @StateObject private var phoneDetector = PhoneDetector()
    @StateObject private var robotController: AnyRobotController

    @State private var selectedMinutes: Int? = nil
    @State private var customSelected = false
    @State private var customHours = ""
    @State private var customMinutes = ""
    @State private var noTimeSelected = false
    @State private var showCustomPopup = false
    @FocusState private var customTimeFocus: CustomTimeField?
    @State private var showTimerDropdown = false

    @State private var showInfo = false
    @State private var userAllowedCamera = false

    @State private var lastSittingAlertAt: Date?
    @State private var lastPhoneAlertAt: Date?
    private let reAlertCooldown: TimeInterval = 30


    private var cameraActive: Bool {
        userAllowedCamera && camera.isAuthorized
    }

    private var effectiveMinutes: Int? {
        guard !noTimeSelected else { return nil }
        if customSelected {
            let h = Int(customHours) ?? 0
            let m = Int(customMinutes) ?? 0
            let total = h * 60 + m
            return total > 0 ? total : nil
        }
        return selectedMinutes
    }

    private var canStart: Bool {
        noTimeSelected || effectiveMinutes != nil
    }

    private var timerLabel: String {
        if noTimeSelected { return "No time" }
        if customSelected {
            let h = Int(customHours) ?? 0
            let m = Int(customMinutes) ?? 0
            if h > 0 && m > 0 { return "Timer (\(h)h \(m)m)" }
            if h > 0 { return "Timer (\(h)h)" }
            if m > 0 { return "Timer (\(m) mins)" }
            return "Custom"
        }
        if let mins = selectedMinutes { return "Timer (\(mins) mins)" }
        return "Select timer"
    }

    private var displaySeconds: Int {
        if let mins = focusStore.targetMinutes {
            return max(0, mins * 60 - focusStore.currentSeconds)
        }
        return focusStore.currentSeconds
    }

    private var elapsedFormatted: String {
        String(format: "%02d:%02d", displaySeconds / 60, displaySeconds % 60)
    }

    private var timerSuffix: String {
        focusStore.targetMinutes != nil ? "remaining" : "elapsed"
    }

    private let sittingLimit: TimeInterval = 15 * 60
    private let phoneLimit: TimeInterval = 10

    init(serial: SerialManager, connectionSettings: RobotConnectionSettings) {
        self.serial = serial
        let robotController = AnyRobotController(serial: serial, settings: connectionSettings)
        _robotController = StateObject(wrappedValue: robotController)
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let columnWidth = geo.size.width * 0.25

                HStack(alignment: .top, spacing: 40) {
                    leftPanel
                        .frame(width: columnWidth)
                        .padding(.top, 32)

                    rightPanel
                        .frame(width: columnWidth * 2)
                        .padding(.top, 32)
                        .padding(.bottom, 32)

                    Color.clear
                        .frame(width: columnWidth)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture {
                    if showInfo { showInfo = false }
                    if showTimerDropdown { showTimerDropdown = false }
                }
            }

            if showCustomPopup {
                customTimePopup
            }
        }
        // Dropdown is drawn here, above the entire page (camera + control card
        // and its border), and positioned from the button's published anchor —
        // so nothing can paint over it and it lands just below the button.
        .overlayPreferenceValue(TimerAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if showTimerDropdown, let anchor {
                    let rect = proxy[anchor]

                    // Invisible full-screen catcher: tap outside to dismiss.
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture { showTimerDropdown = false }

                    timerOptionsList
                        .frame(width: rect.width)
                        .offset(x: rect.minX, y: rect.maxY + 4)
                }
            }
        }
        .onDisappear { camera.stop() }
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
            customSelected = false
            customHours = ""
            customMinutes = ""
            focusStore.start()
        }
        .onChange(of: posture.currentDuration) { _, _ in checkSittingThreshold() }
        .onChange(of: phoneDetector.currentDuration) { _, _ in checkPhoneThreshold() }
    }

    // MARK: - Threshold alerts

    private func checkSittingThreshold() {
        guard posture.currentPosture == .sitting else { return }
        guard posture.currentDuration >= sittingLimit else { return }
        guard shouldAlert(lastSittingAlertAt) else { return }
        lastSittingAlertAt = Date()
        robotController.sendCommand("ANGRY")
    }

    private func checkPhoneThreshold() {
        guard phoneDetector.isPhoneDetected else { return }
        guard phoneDetector.currentDuration >= phoneLimit else { return }
        guard shouldAlert(lastPhoneAlertAt) else { return }
        lastPhoneAlertAt = Date()
        robotController.sendCommand("ANGRY")
    }

    private func shouldAlert(_ last: Date?) -> Bool {
        guard let last else { return true }
        return Date().timeIntervalSince(last) >= reAlertCooldown
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BOCAM")
                .font(Bocil.header(32))
                .foregroundColor(Bocil.ink)

            Text("Bocil Camera will watch you and accompany you during your deep work session.")
                .font(Bocil.mono(14))
                .foregroundColor(Bocil.subtext)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        VStack(spacing: 12) {
            Group {
                if cameraActive {
                    CameraPreviewView(session: camera.session)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                        .clipShape(Rectangle())
                } else {
                    permissionCard
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16/9, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if focusStore.sessionActive && cameraActive {
                    bocilIsWatchingBadge
                }
            }
            .overlay(alignment: .bottomLeading) {
                if cameraActive {
                    HStack(spacing: 8) {
                        phoneStatusBadge
                        postureStatusBadge
                    }
                    .padding(10)
                }
            }
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

            if cameraActive {
                controlCard
            }
        }
    }

    // MARK: - Bocil is watching badge

    private var bocilIsWatchingBadge: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Bocil.accentSoft)
                .frame(width: 7, height: 7)
            Text("Bocil is watching")
                .font(Bocil.mono(12))
                .foregroundColor(Bocil.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Bocil.surface.opacity(0.92))
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1))
        .padding(10)
    }

    // MARK: - Status badges

    private var phoneStatusBadge: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(phoneDetector.isPhoneDetected ? Color.orange : Color.gray.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(phoneDetector.isPhoneDetected ? "On phone" : "Not on phone")
                .font(Bocil.mono(12))
                .foregroundColor(Bocil.ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Bocil.surface.opacity(0.92))
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1))
    }

    private var postureStatusBadge: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(posture.currentPosture == .sitting ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(posture.currentPosture?.rawValue ?? (posture.isCalibrated ? "—" : "Calibrating…"))
                .font(Bocil.mono(12))
                .foregroundColor(Bocil.ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Bocil.surface.opacity(0.92))
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1))
    }

    // MARK: - Control card

    private var controlCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(focusStore.sessionActive ? "DEEP WORK ACTIVE" : "DEEP WORK")
                    .font(Bocil.header(20))
                    .foregroundColor(Bocil.ink)
                Text(focusStore.sessionActive
                     ? "\(elapsedFormatted) \(timerSuffix)"
                     : "Mute nudges and let Bocil watch quietly")
                    .font(Bocil.mono(14))
                    .foregroundColor(Bocil.subtext)
            }
            Spacer()
            if !focusStore.sessionActive {
                timerDropdown
            }
            sessionActionButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    // MARK: - Timer dropdown

    private var timerDropdown: some View {
        Button { showTimerDropdown.toggle() } label: {
            HStack(spacing: 12) {
                Text(timerLabel)
                    .font(Bocil.mono(13))
                    .foregroundColor(timerLabel == "Select timer" ? Bocil.subtext : Bocil.ink)
                Image("ChevronDownPixel")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundColor(Bocil.subtext)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Bocil.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().stroke(Bocil.accentSoft, lineWidth: 1.5))
        .anchorPreference(key: TimerAnchorKey.self, value: .bounds) { $0 }
    }

    private var timerOptionsList: some View {
        VStack(spacing: 0) {
            ForEach(timerOptions, id: \.label) { option in
                Button {
                    option.action()
                    showTimerDropdown = false
                } label: {
                    Text(option.label)
                        .font(Bocil.mono(13))
                        .foregroundColor(Bocil.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Bocil.surface)
                }
                .buttonStyle(.plain)
                if option.label != timerOptions.last?.label {
                    Rectangle().fill(Bocil.accentSoft).frame(height: 1)
                }
            }
        }
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.accentSoft, lineWidth: 1.5))
    }

    private struct TimerOption {
        let label: String
        let action: () -> Void
    }

    private var timerOptions: [TimerOption] {
        [
            TimerOption(label: "30 Minutes") {
                selectedMinutes = 30; noTimeSelected = false
                customSelected = false; customHours = ""; customMinutes = ""
            },
            TimerOption(label: "60 Minutes") {
                selectedMinutes = 60; noTimeSelected = false
                customSelected = false; customHours = ""; customMinutes = ""
            },
            TimerOption(label: "No time") {
                noTimeSelected = true; selectedMinutes = nil
                customSelected = false; customHours = ""; customMinutes = ""
            },
            TimerOption(label: "Custom") {
                showCustomPopup = true
            }
        ]
    }

    // MARK: - Session action button

    @ViewBuilder
    private var sessionActionButton: some View {
        if focusStore.sessionActive {
            Button("END SESSION") {
                focusStore.stop()
            }
            .font(Bocil.header(13))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(Bocil.danger)
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        } else {
            Button("Start") {
                guard canStart else { return }
                focusStore.start(limitMinutes: effectiveMinutes)
                lastSittingAlertAt = nil
                lastPhoneAlertAt = nil
            }
            .font(Bocil.header(13))
            .foregroundColor(Bocil.ink)
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(canStart ? Bocil.accentSoft : Bocil.hairline)
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Custom time popup

    private var customTimePopup: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    showCustomPopup = false
                    if !customSelected && selectedMinutes == nil && !noTimeSelected {
                        selectedMinutes = 30
                    }
                }

            VStack(alignment: .leading, spacing: 24) {
                Text("ENTER TIME")
                    .font(Bocil.header(13))
                    .foregroundColor(Bocil.subtext)

                HStack(alignment: .bottom, spacing: 12) {
                    // Hour field
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack {
                            Rectangle()
                                .fill(customTimeFocus == .hours ? Bocil.surface : Bocil.hairline)
                                .overlay(
                                    Rectangle().stroke(
                                        customTimeFocus == .hours ? Bocil.accentSoft : Color.clear,
                                        lineWidth: 2
                                    )
                                )
                            TextField("", text: $customHours)
                                .textFieldStyle(.plain)
                                .font(Bocil.header(36))
                                .foregroundColor(Bocil.ink)
                                .multilineTextAlignment(.center)
                                .focused($customTimeFocus, equals: .hours)
                        }
                        .frame(width: 110, height: 80)

                        Text("Hour")
                            .font(Bocil.mono(12))
                            .foregroundColor(Bocil.subtext)
                    }

                    // Colon dots
                    VStack(spacing: 6) {
                        Circle().fill(Bocil.ink).frame(width: 6, height: 6)
                        Circle().fill(Bocil.ink).frame(width: 6, height: 6)
                    }
                    .padding(.bottom, 26)

                    // Minute field
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack {
                            Rectangle()
                                .fill(customTimeFocus == .minutes ? Bocil.surface : Bocil.hairline)
                                .overlay(
                                    Rectangle().stroke(
                                        customTimeFocus == .minutes ? Bocil.accentSoft : Color.clear,
                                        lineWidth: 2
                                    )
                                )
                            TextField("00", text: $customMinutes)
                                .textFieldStyle(.plain)
                                .font(Bocil.header(36))
                                .foregroundColor(Bocil.ink)
                                .multilineTextAlignment(.center)
                                .focused($customTimeFocus, equals: .minutes)
                        }
                        .frame(width: 110, height: 80)

                        Text("Minute")
                            .font(Bocil.mono(12))
                            .foregroundColor(Bocil.subtext)
                    }
                }

                HStack {
                    Spacer()
                    Button("CANCEL") {
                        showCustomPopup = false
                        customSelected = false
                        customHours = ""
                        customMinutes = ""
                        if selectedMinutes == nil && !noTimeSelected {
                            selectedMinutes = 30
                        }
                    }
                    .font(Bocil.header(13))
                    .foregroundColor(Bocil.subtext)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    Button("OK") {
                        customSelected = true
                        selectedMinutes = nil
                        noTimeSelected = false
                        showCustomPopup = false
                    }
                    .font(Bocil.header(13))
                    .foregroundColor(Bocil.accentSoft)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .disabled({
                        let h = Int(customHours) ?? 0
                        let m = Int(customMinutes) ?? 0
                        return h * 60 + m == 0
                    }())
                }
            }
            .padding(32)
            .background(Bocil.surface)
            .overlay(Rectangle().stroke(Bocil.accentSoft, lineWidth: 2))
            .frame(width: 360)
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

    private enum CustomTimeField: Hashable { case hours, minutes }

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
    FocusView(serial: SerialManager(), connectionSettings: RobotConnectionSettings())
        .environmentObject(FocusStore())
}
