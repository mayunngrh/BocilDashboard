import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appearanceManager: AppearanceManager
    @EnvironmentObject private var languageManager: AppLanguageManager
    @Environment(\.locale) private var locale
    @ObservedObject var connectionSettings: RobotConnectionSettings
    @StateObject private var memoryService = MemoryBackendService()
    @StateObject private var configService = ConfigBackendService()
    @StateObject private var backendConfig = BackendConfigStore()

    @State private var personality: PersonalityMode = .calm
    @State private var taskReminders      = true
    @State private var calendarAlerts     = true
    @State private var remindBefore       = 10
    @State private var cameraAccess       = true
    @State private var personalizationData = true
    @State private var hoveredMemoryID: String? = nil
    @State private var draftServerURL: String = ""

    private let remindOptions = [5, 10, 15, 30]

    // Three content-sized columns instead of a fixed grid — each card sizes to
    // its own content rather than stretching to match a row, so the page's
    // total height is the tallest column's actual content, not an arbitrary
    // row count. That's what keeps everything on one screen without a
    // leftover empty cell (the old 2-column grid had 5 cards in 3 rows, with
    // an empty cell wasting space in the last row and pushing Appearance below
    // the fold). Still wrapped in a ScrollView as a safety net for very short
    // windows or an unusually long memory list, but it shouldn't engage at
    // the app's normal minimum size.
    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 20) {
                    personalityCard
                    connectionCard
                    serverCard
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 20) {
                    notificationsCard
                    privacyCard
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 20) {
                    appearanceCard
                }
                .frame(maxWidth: .infinity)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await memoryService.fetchMemories() }
        .task { await loadConfig() }
        .onAppear { draftServerURL = backendConfig.baseURL }
    }

    /// Loads server config and reflects the saved personality and notification settings in the UI.
    private func loadConfig() async {
        await configService.fetchConfig()

        // Load personality
        if let value = configService.config?.personality,
           let mode = PersonalityMode(apiValue: value) {
            personality = mode
        }

        // Load notification settings
        if let notif = configService.config?.notifications {
            if let taskReminders = notif.taskReminders {
                self.taskReminders = taskReminders
            }
            if let calendarAlerts = notif.calendarAlerts {
                self.calendarAlerts = calendarAlerts
            }
            if let remindBefore = notif.remindBeforeMinutes {
                self.remindBefore = remindBefore
            }
        }
    }

    private var personalityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.personality.title")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            VStack(spacing: 8) {
                ForEach(PersonalityMode.allCases, id: \.self) { mode in
                    Button(action: {
                        personality = mode
                        Task { await configService.updatePersonality(mode.apiValue) }
                    }) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mode.titleKey)
                                .font(Bocil.header(16))
                                .foregroundColor(personality == mode ? Bocil.onAccent : Bocil.ink)
                            Text(mode.subtitleKey)
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
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.connection.title")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            HStack(spacing: 8) {
                ForEach(RobotConnectionMode.allCases, id: \.self) { mode in
                    Button(action: { connectionSettings.mode = mode }) {
                        Text(mode.labelKey)
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
                    Text("settings.connection.ipAddress")
                        .font(Bocil.mono(12))
                        .foregroundColor(Bocil.subtext)
                    TextField("settings.connection.ipPlaceholder", text: $connectionSettings.wifiHost)
                        .textFieldStyle(.plain)
                        .font(Bocil.mono(13))
                        .foregroundColor(Bocil.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                    Text("settings.connection.ipHint")
                        .font(Bocil.mono(10))
                        .foregroundColor(Bocil.faint)
                }
            }

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            HStack {
                Text(connectionSettings.mode == .wifi
                     ? (connectionSettings.wifiHost.isEmpty ? String(localized: "settings.connection.noIP", locale: locale) : connectionSettings.wifiHost)
                     : String(localized: "settings.connection.usbSerial", locale: locale))
                    .font(Bocil.mono(14))
                    .foregroundColor(Bocil.ink)
                Spacer()
                Rectangle().fill(Bocil.accentSoft).frame(width: 8, height: 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    // MARK: - Backend server
    //
    // BackendConfig.baseURL is what every API service (Profile, Calendar,
    // Config, Tasks, Memory, History, audio playback) talks to — separate
    // from `connectionCard` above, which is the robot's own WiFi/serial link.
    // Services read BackendConfig.baseURL live (not cached at init), so a
    // saved change here takes effect on the very next network call, no
    // restart needed.

    private var serverCard: some View {
        let isDirty = draftServerURL.trimmingCharacters(in: .whitespacesAndNewlines) != backendConfig.baseURL
        let isDefault = backendConfig.baseURL == BackendConfig.defaultBaseURL

        return VStack(alignment: .leading, spacing: 16) {
            Text("settings.server.title")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            VStack(alignment: .leading, spacing: 6) {
                Text("settings.server.urlLabel")
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.subtext)
                TextField("settings.server.urlPlaceholder", text: $draftServerURL)
                    .textFieldStyle(.plain)
                    .font(Bocil.mono(13))
                    .foregroundColor(Bocil.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                    .onSubmit { saveServerURL() }
                Text("settings.server.hint")
                    .font(Bocil.mono(10))
                    .foregroundColor(Bocil.faint)
            }

            HStack(spacing: 8) {
                Button(action: saveServerURL) {
                    Text("common.save")
                        .font(Bocil.mono(12))
                        .foregroundColor(Bocil.onAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Bocil.accentSoft)
                }
                .buttonStyle(.plain)
                .disabled(!isDirty || draftServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(isDirty ? 1 : 0.4)

                Button(action: {
                    backendConfig.resetToDefault()
                    draftServerURL = backendConfig.baseURL
                }) {
                    Text("settings.server.resetToDefault")
                        .font(Bocil.mono(12))
                        .foregroundColor(Bocil.subtext)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(isDefault)
                .opacity(isDefault ? 0.4 : 1)
            }

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            // Current connection, styled like the top navbar's status pill.
            HStack(spacing: 6) {
                Rectangle().fill(Bocil.accentSoft).frame(width: 7, height: 7)
                Text(backendConfig.baseURL)
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private func saveServerURL() {
        let trimmed = draftServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        backendConfig.baseURL = trimmed
        draftServerURL = trimmed
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.notifications.title")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            toggleRow(label: "settings.notifications.taskReminders", isOn: $taskReminders)
                .onChange(of: taskReminders) { _, newValue in
                    Task { await configService.updateNotifications(taskReminders: newValue) }
                }

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            toggleRow(label: "settings.notifications.calendarAlerts", isOn: $calendarAlerts)
                .onChange(of: calendarAlerts) { _, newValue in
                    Task { await configService.updateNotifications(calendarAlerts: newValue) }
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("settings.notifications.remindBefore")
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.subtext)

                HStack(spacing: 8) {
                    ForEach(remindOptions, id: \.self) { min in
                        Button(action: {
                            remindBefore = min
                            Task { await configService.updateNotifications(remindBeforeMinutes: min) }
                        }) {
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
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.privacy.title")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            toggleRow(label: "settings.privacy.camera",
                      caption: "settings.privacy.camera.caption",
                      isOn: $cameraAccess)
            Rectangle().fill(Bocil.hairline).frame(height: 1)
            toggleRow(label: "settings.privacy.personalization",
                      caption: "settings.privacy.personalization.caption",
                      isOn: $personalizationData)

            Rectangle().fill(Bocil.hairline).frame(height: 1)
                .padding(.vertical, 4)

            memorySection
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .top)
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
                Text("settings.memory.title")
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
                    Button("common.retry") { Task { await memoryService.fetchMemories() } }
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.ink)
                        .buttonStyle(.plain)
                }
            }

            if memoryService.memories.isEmpty && !memoryService.isLoading {
                Text("settings.memory.empty")
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
                .frame(maxHeight: 160)
            }

            Button(action: { Task { await memoryService.clearAll() } }) {
                Text("settings.memory.clear")
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
            Text("settings.appearance.title")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            VStack(spacing: 8) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button(action: { appearanceManager.mode = mode }) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mode.titleKey)
                                .font(Bocil.header(16))
                                .foregroundColor(appearanceManager.mode == mode ? Bocil.onAccent : Bocil.ink)
                            Text(mode.subtitleKey)
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

            Text("settings.language.title")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            VStack(spacing: 8) {
                ForEach(LanguageMode.allCases, id: \.self) { mode in
                    Button(action: { languageManager.mode = mode }) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mode.titleKey)
                                .font(Bocil.header(16))
                                .foregroundColor(languageManager.mode == mode ? Bocil.onAccent : Bocil.ink)
                            Text(mode.subtitle)
                                .font(Bocil.mono(14))
                                .foregroundColor(languageManager.mode == mode ? Bocil.onAccent : Bocil.subtext)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(languageManager.mode == mode ? Bocil.accentSoft : Bocil.surface)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    @ViewBuilder
    private func toggleRow(label: LocalizedStringKey, caption: LocalizedStringKey? = nil, isOn: Binding<Bool>) -> some View {
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
        .environmentObject(AppLanguageManager())
}
