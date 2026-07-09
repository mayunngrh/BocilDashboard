import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    var onOpenCalendar: () -> Void = {}
    var onOpenFocus:    () -> Void = {}
    var onStartFocus:   () -> Void = {}

    /// Shared with `AppView`'s top nav bar — the floating nav next to the
    /// robot writes to the same selection, so tapping it switches tabs exactly
    /// like clicking the top bar.
    @Binding var selectedTab: BocilTab

    @EnvironmentObject private var focusStore:     FocusStore
    @EnvironmentObject private var profileService: ProfileBackendService
    // String(localized:) does NOT follow .environment(\.locale) automatically
    // (unlike Text(LocalizedStringKey)) — it needs the locale passed explicitly,
    // which is why every String(localized:) call below passes `locale: locale`.
    @Environment(\.locale) private var locale

    // The summary reads live backend data, not the local CalendarStore.
    @StateObject private var calendarBackend = CalendarBackendService()
    @StateObject private var tasksBackend     = TasksBackendService()

    // Kept as an offline cache; the backend profile is the source of truth and
    // overwrites these on load (see loadProfile()).
    @AppStorage("bocil.home.name") private var userName: String = ""
    @AppStorage("bocil.home.role") private var roleText: String = ""

    @State private var isEditing = false
    @State private var draftName = ""
    @State private var draftRole = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var roleFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            leftPanel
            rightPanel.frame(width: 380)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await loadHomeData() }
    }

    /// Loads everything the Home page shows from the backend: the profile
    /// (name/role/focus) plus today's calendar events and tasks that feed the
    /// summary. Runs its three fetches concurrently.
    private func loadHomeData() async {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let endOfMonth = cal.date(byAdding: .month, value: 1, to: startOfMonth)!

        async let profileFetch: Void = profileService.fetchProfile()
        async let eventsFetch: Void = calendarBackend.fetchEvents(from: startOfMonth, to: endOfMonth)
        async let tasksFetch: Void = tasksBackend.fetchTasks()
        _ = await (profileFetch, eventsFetch, tasksFetch)

        // Seed local caches from the profile (only overwrite name/role when the
        // server actually has a value, so a locally set name isn't wiped before
        // the first save syncs it up).
        if let profile = profileService.profile {
            if let name = profile.name, !name.isEmpty { userName = name }
            if let role = profile.role, !role.isEmpty { roleText = role }
            focusStore.seedTodayFocus(seconds: profile.focusSecondsToday)
        }
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        ZStack(alignment: .topLeading) {
            // Robot + orbiting nav sit behind, filling the full panel. The
            // scaleEffect shrinks the rendered cluster 30% without changing
            // its reserved layout size, which opens a margin on every edge —
            // that's what keeps the orbit badges (which sit slightly outside
            // the robot image) from clipping at the panel's bounds, at any
            // window size.
            ZStack {
                RobotEyeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                FloatingOrbitNav(selectedTab: $selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .scaleEffect(0.7)
            .offset(x: 60)

            // Greeting floats on top, anchored top-leading.
            Text(greetingLine)
                .font(Bocil.header(36))
                .foregroundColor(Bocil.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        VStack(spacing: 14) {
            whoAmICard
            summaryCard
            ctaCard
        }
    }

    // MARK: - WHO AM I card

    private var whoAmICard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("home.whoAmI.title")
                    .font(Bocil.header(16))
                    .foregroundColor(Bocil.ink)
                Spacer()
                Button(action: { isEditing ? saveEditing() : startEditing(focusingName: true) }) {
                    Group {
                        if isEditing {
                            Text("common.save")
                                .font(Bocil.mono(14))
                        } else {
                            Image("PencilPixel")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 12)
                        }
                    }
                    .foregroundColor(isEditing ? Bocil.onAccent : Bocil.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isEditing ? Bocil.accentSoft : Color.clear)
                    .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            Group {
                if isEditing {
                    TextField("home.whoAmI.namePlaceholder", text: $draftName)
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .onSubmit { roleFocused = true }
                } else {
                    Text(userName.isEmpty ? String(localized: "home.whoAmI.namePlaceholder", locale: locale) : userName)
                        .foregroundColor(userName.isEmpty ? Bocil.faint : Bocil.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { startEditing(focusingName: true) }
                }
            }
            .font(Bocil.mono(18))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if isEditing {
                        TextField("home.whoAmI.rolePlaceholder", text: $draftRole)
                            .textFieldStyle(.plain)
                            .focused($roleFocused)
                            .onSubmit { saveEditing() }
                    } else {
                        Text(roleText.isEmpty ? String(localized: "home.whoAmI.rolePlaceholder", locale: locale) : roleText)
                            .foregroundColor(roleText.isEmpty ? Bocil.faint : Bocil.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { startEditing(focusingName: false) }
                    }
                }
                .font(Bocil.mono(18))
                Text("home.whoAmI.roleHint")
                    .font(Bocil.mono(14))
                    .foregroundColor(Bocil.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
        .onChange(of: nameFocused) { _, _ in maybeAutoSave() }
        .onChange(of: roleFocused) { _, _ in maybeAutoSave() }
    }

    // MARK: - Summary card

    // Today's backend events, soonest first.
    private var todayBackendEvents: [BackendCalendarEvent] {
        let cal = Calendar.current
        return calendarBackend.events
            .filter { cal.isDate($0.startsAt, inSameDayAs: Date()) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    // All of today's events (regardless of whether they've started).
    private var todayEventCount: Int { todayBackendEvents.count }

    // Is there still an event later today? (drives the "next in …" sub-label)
    private var hasUpcomingEvent: Bool {
        let now = Date()
        return todayBackendEvents.contains { $0.startsAt > now }
    }

    // Open (incomplete) tasks — the "tiny quests" still to do.
    private var openTaskCount: Int {
        tasksBackend.tasks.filter { !($0.completed ?? false) }.count
    }

    private var focusMinutes: Int { focusStore.totalTodayMinutes }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("home.summary.title")
                .font(Bocil.header(16))
                .foregroundColor(Bocil.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            summaryRow(
                icon:   "CalendarPixel",
                value:  todayEventCount == 0 ? "0" : "\(todayEventCount)",
                label:  todayEventCount == 0 ? String(localized: "home.summary.calendar.empty", locale: locale)
                        : todayEventCount == 1 ? String(localized: "home.summary.calendar.one", locale: locale)
                        : String(localized: "home.summary.calendar.other", locale: locale),
                sub:    hasUpcomingEvent ? minsUntilNextText : "",
                empty:  todayEventCount == 0,
                action: onOpenCalendar
            )
            Rectangle().fill(Bocil.hairline).frame(height: 1)
            summaryRow(
                icon:   "ListPixel",
                value:  openTaskCount == 0 ? "0" : "\(openTaskCount)",
                label:  openTaskCount == 0 ? String(localized: "home.summary.tasks.empty", locale: locale)
                        : openTaskCount == 1 ? String(localized: "home.summary.tasks.one", locale: locale)
                        : String(localized: "home.summary.tasks.other", locale: locale),
                sub:    openTaskCount == 0 ? "" : String(localized: "home.summary.tasks.sub", locale: locale),
                empty:  openTaskCount == 0,
                action: onOpenCalendar
            )
            Rectangle().fill(Bocil.hairline).frame(height: 1)
            summaryRow(
                icon:   "TimePixel",
                value:  focusMinutes == 0 ? "0h" : focusValueText,
                label:  focusMinutes == 0 ? String(localized: "home.summary.focus.empty", locale: locale)
                        : String(localized: "home.summary.focus.label", locale: locale),
                sub:    focusMinutes == 0 ? "" : String(localized: "common.today", locale: locale),
                empty:  focusMinutes == 0,
                action: onOpenFocus
            )
        }
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private func summaryRow(icon: String, value: String, label: String,
                             sub: String, empty: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundColor(empty ? Bocil.faint : Bocil.subtext)
                .frame(width: 18)
            Text(value)
                .font(Bocil.mono(20))
                .foregroundColor(empty ? Bocil.faint : Bocil.accentSoft)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(label)
                    .font(Bocil.mono(16))
                    .foregroundColor(empty ? Bocil.faint : Bocil.ink)
                    .multilineTextAlignment(.trailing)
                if !sub.isEmpty {
                    Text(sub)
                        .font(Bocil.mono(14))
                        .foregroundColor(Bocil.subtext)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    private var minsUntilNextText: String {
        let now = Date()
        guard let next = todayBackendEvents.first(where: { $0.startsAt > now }) else {
            return String(localized: "common.today", locale: locale)
        }
        let mins = max(1, Int(next.startsAt.timeIntervalSince(now) / 60))
        if mins < 60 {
            return String(format: String(localized: "home.summary.inMinutes", locale: locale), mins)
        }
        return String(format: String(localized: "home.summary.inHoursMinutes", locale: locale), mins / 60, mins % 60)
    }

    private var focusValueText: String {
        let h = focusMinutes / 60
        let m = focusMinutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: - CTA card

    private var ctaCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("home.cta.title")
                    .font(Bocil.header(16))
                    .foregroundColor(Bocil.ink)
                Text("home.cta.subtitle")
                    .font(Bocil.mono(16))
                    .foregroundColor(Bocil.subtext)
            }
            Spacer()
            Button("common.start") { onStartFocus() }
                .font(Bocil.mono(16))
                .foregroundColor(Bocil.onAccent)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(Bocil.accentSoft)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    // MARK: - Greeting

    private var greetingLine: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        let prefix: String
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  prefix = String(localized: "home.greeting.morning", locale: locale)
        case 12..<17: prefix = String(localized: "home.greeting.afternoon", locale: locale)
        case 17..<21: prefix = String(localized: "home.greeting.evening", locale: locale)
        default:       prefix = String(localized: "home.greeting.night", locale: locale)
        }
        return name.isEmpty ? "\(prefix)." : "\(prefix), \(name.uppercased())."
    }

    // MARK: - Edit helpers

    private func startEditing(focusingName: Bool) {
        draftName = userName
        draftRole = roleText
        isEditing = true
        if focusingName { nameFocused = true } else { roleFocused = true }
    }

    private func saveEditing() {
        guard isEditing else { return }
        userName = draftName.trimmingCharacters(in: .whitespaces)
        roleText = draftRole.trimmingCharacters(in: .whitespaces)
        isEditing = false
        Task { await profileService.updateProfile(name: userName, role: roleText) }
    }

    private func maybeAutoSave() {
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            if isEditing && !nameFocused && !roleFocused {
                saveEditing()
            }
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .environmentObject(AppearanceManager())
        .environmentObject(CalendarStore())
        .environmentObject(FocusStore())
        .environmentObject(ProfileBackendService())
        .frame(width: 1100, height: 700)
}
