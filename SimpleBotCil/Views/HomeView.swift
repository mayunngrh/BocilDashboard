import SwiftUI

// MARK: - Speech bubble shape (tail at bottom-right)

private struct SpeechBubbleShape: Shape {
    var tailHeight: CGFloat = 16
    var tailWidth:  CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bubbleBottom = rect.maxY - tailHeight

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // right edge continues all the way to tail tip
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // diagonal back up to tail base
        path.addLine(to: CGPoint(x: rect.maxX - tailWidth, y: bubbleBottom))
        // rest of bottom edge
        path.addLine(to: CGPoint(x: rect.minX, y: bubbleBottom))
        path.closeSubpath()

        return path
    }
}

// MARK: - HomeView

struct HomeView: View {
    var onOpenCalendar: () -> Void = {}
    var onOpenFocus:    () -> Void = {}
    var onStartFocus:   () -> Void = {}

    @EnvironmentObject private var focusStore:     FocusStore
    @EnvironmentObject private var profileService: ProfileBackendService

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
            Spacer()
            robotEye.frame(width: 200, height: 200)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await loadHomeData() }
    }

    private var robotEye: some View {
        RobotEyeView()
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
        VStack(alignment: .leading, spacing: 20) {
            Text(greetingLine)
                .font(Bocil.header(36))
                .foregroundColor(Bocil.ink)

            speechBubble
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var speechBubble: some View {
        let tailH: CGFloat = 16
        let tailW: CGFloat = 16

        return VStack(alignment: .leading, spacing: 4) {
            Text("I'm Bocil,")
                .font(Bocil.mono(16))
                .foregroundColor(Bocil.ink)
            Text("ready for today?")
                .font(Bocil.mono(16))
                .foregroundColor(Bocil.ink)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16 + tailH)   // reserve space for tail below text
        .frame(maxWidth: 260, alignment: .leading)
        .background(
            SpeechBubbleShape(tailHeight: tailH, tailWidth: tailW)
                .fill(Bocil.surface)
        )
        .overlay(
            SpeechBubbleShape(tailHeight: tailH, tailWidth: tailW)
                .stroke(Bocil.accentSoft, lineWidth: 1.5)
        )
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
                Text("WHO AM I WORKING WITH TODAY?")
                    .font(Bocil.header(16))
                    .foregroundColor(Bocil.ink)
                Spacer()
                Button(action: toggleEditing) {
                    Group {
                        if isEditing {
                            Text("Save")
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
                    TextField("Type your name", text: $draftName)
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .onSubmit { roleFocused = true }
                } else {
                    Text(userName.isEmpty ? "Type your name" : userName)
                        .foregroundColor(userName.isEmpty ? Bocil.faint : Bocil.ink)
                }
            }
            .font(Bocil.mono(18))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if isEditing {
                        TextField("Tell me about your role.", text: $draftRole)
                            .textFieldStyle(.plain)
                            .focused($roleFocused)
                            .onSubmit { toggleEditing() }
                    } else {
                        Text(roleText.isEmpty ? "Tell me about your role." : roleText)
                            .foregroundColor(roleText.isEmpty ? Bocil.faint : Bocil.ink)
                    }
                }
                .font(Bocil.mono(18))
                Text("e.g. student, remote worker, founder,...")
                    .font(Bocil.mono(14))
                    .foregroundColor(Bocil.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
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
            Text("TODAY'S SUMMARY")
                .font(Bocil.header(16))
                .foregroundColor(Bocil.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            summaryRow(
                icon:   "CalendarPixel",
                value:  todayEventCount == 0 ? "0" : "\(todayEventCount)",
                label:  todayEventCount == 0 ? "nothing scary yet"
                        : todayEventCount == 1 ? "event today" : "events today",
                sub:    hasUpcomingEvent ? minsUntilNextText : "",
                empty:  todayEventCount == 0,
                action: onOpenCalendar
            )
            Rectangle().fill(Bocil.hairline).frame(height: 1)
            summaryRow(
                icon:   "ListPixel",
                value:  openTaskCount == 0 ? "0" : "\(openTaskCount)",
                label:  openTaskCount == 0 ? "looks pretty chill"
                        : openTaskCount == 1 ? "tiny quest" : "tiny quests",
                sub:    openTaskCount == 0 ? "" : "to do",
                empty:  openTaskCount == 0,
                action: onOpenCalendar
            )
            Rectangle().fill(Bocil.hairline).frame(height: 1)
            summaryRow(
                icon:   "TimePixel",
                value:  focusMinutes == 0 ? "0h" : focusValueText,
                label:  focusMinutes == 0 ? "you haven't locked in today" : "focus time spent",
                sub:    focusMinutes == 0 ? "" : "today",
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
        guard let next = todayBackendEvents.first(where: { $0.startsAt > now }) else { return "today" }
        let mins = max(1, Int(next.startsAt.timeIntervalSince(now) / 60))
        return mins < 60 ? "in \(mins) min" : "in \(mins / 60)h \(mins % 60)m"
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
                Text("Ready to lock in?")
                    .font(Bocil.header(16))
                    .foregroundColor(Bocil.ink)
                Text("Let me accompany you")
                    .font(Bocil.mono(16))
                    .foregroundColor(Bocil.subtext)
            }
            Spacer()
            Button("Start") { onStartFocus() }
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
        case 5..<12:  prefix = "GOOD MORNING"
        case 12..<17: prefix = "GOOD AFTERNOON"
        case 17..<21: prefix = "GOOD EVENING"
        default:       prefix = "GOOD NIGHT"
        }
        return name.isEmpty ? "\(prefix)." : "\(prefix), \(name.uppercased())."
    }

    // MARK: - Edit helpers

    private func toggleEditing() {
        if isEditing {
            userName = draftName.trimmingCharacters(in: .whitespaces)
            roleText = draftRole.trimmingCharacters(in: .whitespaces)
            isEditing = false
            Task { await profileService.updateProfile(name: userName, role: roleText) }
        } else {
            draftName = userName
            draftRole = roleText
            isEditing = true
            nameFocused = true
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppearanceManager())
        .environmentObject(CalendarStore())
        .environmentObject(FocusStore())
        .environmentObject(ProfileBackendService())
        .frame(width: 1100, height: 700)
}
