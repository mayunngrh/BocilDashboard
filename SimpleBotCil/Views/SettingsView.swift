import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appearanceManager: AppearanceManager
    @ObservedObject var connectionSettings: RobotConnectionSettings
    @StateObject private var memoryService = MemoryBackendService()
    @StateObject private var configService = ConfigBackendService()

    @State private var personality: PersonalityMode = .calm
    @State private var language: LanguageMode       = .english
    @State private var taskReminders      = true
    @State private var calendarAlerts     = true
    @State private var remindBefore       = 10
    @State private var cameraAccess       = true
    @State private var personalizationData = true
    @State private var hoveredMemoryID: String? = nil

    private let remindOptions = [5, 10, 15, 30]

    var body: some View {
        ScrollView {
            Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 20) {
                GridRow(alignment: .top) {
                    personalityCard
                    notificationsCard
                }
                GridRow(alignment: .top) {
                    connectionCard
                    privacyCard
                }
                GridRow(alignment: .top) {
                    appearanceCard
                    Color.clear
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await memoryService.fetchMemories() }
        .task { await loadConfig() }
    }

    /// Loads server config and reflects the saved personality in the UI.
    private func loadConfig() async {
        await configService.fetchConfig()
        if let value = configService.config?.personality,
           let mode = PersonalityMode(apiValue: value) {
            personality = mode
        }
    }

    private var personalityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PERSONALITY")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            VStack(spacing: 8) {
                ForEach(PersonalityMode.allCases, id: \.self) { mode in
                    Button(action: {
                        personality = mode
                        Task { await configService.updatePersonality(mode.apiValue) }
                    }) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mode.rawValue)
                                .font(Bocil.header(16))
                                .foregroundColor(personality == mode ? Bocil.onAccent : Bocil.ink)
                            Text(mode.subtitle)
                                .font(Bocil.mono(14))
                                .foregroundColor(personality == mode ? Bocil.onAccent : Bocil.subtext)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(personality == mode ? Bocil.accentSoft : Bocil.surface)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CONNECTION")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            HStack(spacing: 8) {
                ForEach(RobotConnectionMode.allCases, id: \.self) { mode in
                    Button(action: { connectionSettings.mode = mode }) {
                        Text(mode.label)
                            .font(Bocil.mono(12))
                            .foregroundColor(connectionSettings.mode == mode ? Bocil.ink : Bocil.subtext)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(connectionSettings.mode == mode ? Bocil.accentSoft : Color.white)
                            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            if connectionSettings.mode == .wifi {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Robot IP address")
                        .font(Bocil.mono(12))
                        .foregroundColor(Bocil.subtext)
                    TextField("e.g. 10.156.248.250", text: $connectionSettings.wifiHost)
                        .textFieldStyle(.plain)
                        .font(Bocil.mono(13))
                        .foregroundColor(Bocil.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                    Text("Shown in the ESP32 serial log at boot, under [WiFi] Connected!")
                        .font(Bocil.mono(10))
                        .foregroundColor(Bocil.faint)
                }
            }

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            HStack {
                Text(connectionSettings.mode == .wifi ? connectionSettings.wifiHost.isEmpty ? "No IP set" : connectionSettings.wifiHost : "USB Serial")
                    .font(Bocil.mono(14))
                    .foregroundColor(Bocil.ink)
                Spacer()
                Rectangle().fill(Bocil.accentSoft).frame(width: 8, height: 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NOTIFICATIONS")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            toggleRow(label: "Task reminders", isOn: $taskReminders)
            Rectangle().fill(Bocil.hairline).frame(height: 1)
            toggleRow(label: "Calendar alerts", isOn: $calendarAlerts)

            VStack(alignment: .leading, spacing: 10) {
                Text("Remind me before")
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.subtext)

                HStack(spacing: 8) {
                    ForEach(remindOptions, id: \.self) { min in
                        Button(action: { remindBefore = min }) {
                            Text("\(min)m")
                                .font(Bocil.mono(12))
                                .foregroundColor(remindBefore == min ? Bocil.onAccent : Bocil.subtext)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(remindBefore == min ? Bocil.accentSoft : Bocil.surface)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PRIVACY")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            toggleRow(label: "Camera access",
                      caption: "Used for presence and mood in focus mode",
                      isOn: $cameraAccess)
            Rectangle().fill(Bocil.hairline).frame(height: 1)
            toggleRow(label: "Personalization data",
                      caption: "Let's Bocil remember your profile and habits",
                      isOn: $personalizationData)

            Rectangle().fill(Bocil.hairline).frame(height: 1)
                .padding(.vertical, 4)

            memorySection
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    // MARK: - Memory
    //
    // Writes are voice-only (the `memory` tool during a session); this list is
    // read/delete only, per MEMORY_API.md. Gated server-side by
    // privacy.personalizationData — when that's off, GET returns an empty list
    // rather than erroring, so the empty state below covers that case too.

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MEMORY")
                    .font(Bocil.header(20))
                    .foregroundColor(Bocil.ink)
                Spacer()
                if memoryService.isLoading {
                    ProgressView().scaleEffect(0.6)
                }
            }

            if let error = memoryService.error {
                HStack(spacing: 12) {
                    Text(error)
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.danger)
                    Spacer()
                    Button("Retry") { Task { await memoryService.fetchMemories() } }
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.ink)
                        .buttonStyle(.plain)
                }
            }

            if memoryService.memories.isEmpty && !memoryService.isLoading {
                Text("Bocil hasn't remembered anything yet.")
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.faint)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(memoryService.memories) { memory in
                            memoryRow(memory)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Button(action: { Task { await memoryService.clearAll() } }) {
                Text("Clear Bocil's memory")
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().stroke(Bocil.danger, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(memoryService.memories.isEmpty)
            .opacity(memoryService.memories.isEmpty ? 0.4 : 1)
        }
    }

    private func memoryRow(_ memory: MemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(memory.content)
                .font(Bocil.mono(13))
                .foregroundColor(Bocil.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: { Task { await memoryService.deleteMemory(memory) } }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(Bocil.danger)
                    .frame(width: 26, height: 26)
                    .background(hoveredMemoryID == memory.id ? Bocil.danger.opacity(0.15) : Color.clear)
                    .overlay(Rectangle().stroke(Bocil.danger.opacity(hoveredMemoryID == memory.id ? 1 : 0), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredMemoryID = hovering ? memory.id : nil
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Bocil.bg)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("APPEARANCE")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            VStack(spacing: 8) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button(action: { appearanceManager.mode = mode }) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mode.rawValue)
                                .font(Bocil.header(16))
                                .foregroundColor(appearanceManager.mode == mode ? Bocil.onAccent : Bocil.ink)
                            Text(mode.subtitle)
                                .font(Bocil.mono(14))
                                .foregroundColor(appearanceManager.mode == mode ? Bocil.onAccent : Bocil.subtext)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(appearanceManager.mode == mode ? Bocil.accentSoft : Bocil.surface)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(Bocil.hairline).frame(height: 1)
                .padding(.vertical, 4)

            Text("LANGUAGE")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            VStack(spacing: 8) {
                ForEach(LanguageMode.allCases, id: \.self) { mode in
                    Button(action: { language = mode }) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mode.rawValue)
                                .font(Bocil.header(16))
                                .foregroundColor(language == mode ? Bocil.onAccent : Bocil.ink)
                            Text(mode.subtitle)
                                .font(Bocil.mono(14))
                                .foregroundColor(language == mode ? Bocil.onAccent : Bocil.subtext)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(language == mode ? Bocil.accentSoft : Bocil.surface)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    @ViewBuilder
    private func toggleRow(label: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: caption != nil ? .top : .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(Bocil.mono(16))
                    .foregroundColor(Bocil.ink)
                if let caption {
                    Text(caption)
                        .font(Bocil.mono(12))
                        .foregroundColor(Bocil.subtext)
                }
            }
            Spacer()
            PixelToggle(isOn: isOn)
        }
    }
}

#Preview {
    SettingsView(connectionSettings: RobotConnectionSettings())
        .environmentObject(AppearanceManager())
}
