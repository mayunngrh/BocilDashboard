import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appearanceManager: AppearanceManager
    @EnvironmentObject private var languageManager: AppLanguageManager
    @Environment(\.locale) private var locale
    @ObservedObject var connectionSettings: RobotConnectionSettings
    @StateObject private var memoryService = MemoryBackendService()
    @StateObject private var configService = ConfigBackendService()
    @StateObject private var backendConfig = BackendConfigStore()
    @StateObject private var personaService = PersonaBackendService()
    @ObservedObject private var reminderScheduler = LocalReminderScheduler.shared
    // One-shot fetchers used only to re-derive the reminder queue when a
    // notification toggle changes — CalendarView owns the "real" instances
    // that back the UI.
    @StateObject private var reminderTasksService = TasksBackendService()
    @StateObject private var reminderEventsService = CalendarBackendService()

    @State private var taskReminders      = true
    @State private var calendarAlerts     = true
    @State private var remindBefore       = 10
    @AppStorage("bocil.focus.camera.allowed") private var cameraAccess: Bool = false
    @State private var personalizationData = true
    @State private var hoveredMemoryID: String? = nil
    @State private var draftServerURL: String = ""

    // Persona editor overlay. `personaEditorTarget` distinguishes create vs edit:
    // .none = closed, .creating = new character, .editing(name) = existing.
    @State private var personaEditorMode: PersonaEditorMode? = nil

    enum PersonaEditorMode: Equatable {
        case creating
        case editing(String)
    }

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
                    charactersCard
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
        // Re-fetch personas every time Settings appears — the active character
        // can change server-side via voice, so the app never trusts a cache.
        .task { await personaService.fetchPersonas() }
        .task { await refreshReminderQueue() }
        .onAppear { draftServerURL = backendConfig.baseURL }
        .overlay {
            switch personaEditorMode {
            case .creating:
                PersonaEditorView(service: personaService, editingName: nil) {
                    personaEditorMode = nil
                    Task { await personaService.fetchPersonas() }
                }
            case .editing(let name):
                PersonaEditorView(service: personaService, editingName: name) {
                    personaEditorMode = nil
                    Task { await personaService.fetchPersonas() }
                }
            case .none:
                EmptyView()
            }
        }
    }

    /// Loads server config and reflects the saved notification/privacy/appearance settings in the UI.
    private func loadConfig() async {
        await configService.fetchConfig()

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

        // Load privacy settings — personalizationData in particular gates the
        // AI's memory tool server-side, so the toggle must reflect real state.
        if let priv = configService.config?.privacy {
            if let camera = priv.cameraAccess {
                cameraAccess = camera
            }
            if let personalization = priv.personalizationData {
                personalizationData = personalization
            }
        }

        // Load appearance
        if let value = configService.config?.appearance,
           let mode = AppearanceMode(apiValue: value) {
            appearanceManager.mode = mode
        }
    }

    /// Pulls a fresh copy of tasks/events and re-derives the local reminder
    /// queue — called whenever a notification setting changes so the queued
    /// count updates immediately, without waiting for Calendar to reload.
    private func refreshReminderQueue() async {
        async let tasksFetch: Void = reminderTasksService.fetchTasks()
        let calendar = Calendar.current
        let now = Date()
        let from = calendar.date(byAdding: .day, value: -1, to: now)!
        let to = calendar.date(byAdding: .month, value: 2, to: now)!
        async let eventsFetch: Void = reminderEventsService.fetchEvents(from: from, to: to)
        _ = await (tasksFetch, eventsFetch)

        await LocalReminderScheduler.shared.reschedule(
            tasks: reminderTasksService.tasks,
            events: reminderEventsService.events
        )
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

    // MARK: - Characters (personas)
    //
    // Distinct from Personality above: personas are named characters (pirate,
    // grumpy, …) with editable markdown. The active one can change server-side
    // via voice, so this list is re-fetched on every Settings appearance.

    private var charactersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("settings.characters.title")
                    .font(Bocil.header(20))
                    .foregroundColor(Bocil.ink)
                Spacer()
                if personaService.isLoading {
                    ProgressView().scaleEffect(0.6)
                }
            }

            if let error = personaService.error {
                HStack(spacing: 12) {
                    Text(error)
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.danger)
                    Spacer()
                    Button("common.retry") { Task { await personaService.fetchPersonas() } }
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.ink)
                        .buttonStyle(.plain)
                }
            }

            // "None" row — clears back to the plain personality.
            characterRow(name: nil, label: String(localized: "settings.characters.none", locale: locale),
                         isActive: personaService.active == nil, editable: false)

            if personaService.available.isEmpty && !personaService.isLoading {
                Text("settings.characters.empty")
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.faint)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(personaService.available, id: \.self) { name in
                            characterRow(name: name, label: name,
                                         isActive: personaService.active == name, editable: true)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            Button(action: { personaEditorMode = .creating }) {
                Text("settings.characters.new")
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    /// One persona row: tap the name to activate, pencil to edit. `name == nil`
    /// is the "None" row (deactivate); it has no edit affordance.
    private func characterRow(name: String?, label: String, isActive: Bool, editable: Bool) -> some View {
        HStack(spacing: 10) {
            Button(action: { Task { await personaService.activate(name) } }) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(isActive ? Bocil.accentSoft : Color.clear)
                        .frame(width: 8, height: 8)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1))
                    Text(label)
                        .font(Bocil.mono(13))
                        .foregroundColor(Bocil.ink)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if editable, let name {
                Button(action: { personaEditorMode = .editing(name) }) {
                    Image("PencilPixel")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundColor(Bocil.subtext)
                        .frame(width: 26, height: 26)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isActive ? Bocil.accentSoft.opacity(0.15) : Bocil.bg)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.notifications.title")
                .font(Bocil.header(20))
                .foregroundColor(Bocil.ink)

            toggleRow(label: "settings.notifications.taskReminders", isOn: $taskReminders)
                .onChange(of: taskReminders) { _, newValue in
                    Task {
                        await configService.updateNotifications(taskReminders: newValue)
                        await refreshReminderQueue()
                    }
                }

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            toggleRow(label: "settings.notifications.calendarAlerts", isOn: $calendarAlerts)
                .onChange(of: calendarAlerts) { _, newValue in
                    Task {
                        await configService.updateNotifications(calendarAlerts: newValue)
                        await refreshReminderQueue()
                    }
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("settings.notifications.remindBefore")
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.subtext)

                HStack(spacing: 8) {
                    ForEach(remindOptions, id: \.self) { min in
                        Button(action: {
                            remindBefore = min
                            Task {
                                await configService.updateNotifications(remindBeforeMinutes: min)
                                await refreshReminderQueue()
                            }
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

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            Text(String(format: String(localized: "settings.notifications.queued", locale: locale), reminderScheduler.queuedCount))
                .font(Bocil.mono(11))
                .foregroundColor(Bocil.faint)
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
                .onChange(of: cameraAccess) { _, newValue in
                    Task { await configService.updatePrivacy(cameraAccess: newValue) }
                }

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            toggleRow(label: "settings.privacy.personalization",
                      caption: "settings.privacy.personalization.caption",
                      isOn: $personalizationData)
                .onChange(of: personalizationData) { _, newValue in
                    Task { await configService.updatePrivacy(personalizationData: newValue) }
                }

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
                    Button(action: {
                        appearanceManager.mode = mode
                        Task { await configService.updateAppearance(mode.apiValue) }
                    }) {
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
