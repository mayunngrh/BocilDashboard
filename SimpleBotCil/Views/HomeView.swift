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

    @EnvironmentObject private var calendarStore: CalendarStore
    @EnvironmentObject private var focusStore:    FocusStore

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
                    HStack(spacing: 5) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 11, weight: .medium))
                        Text(isEditing ? "Save" : "Edit")
                            .font(Bocil.mono(14))
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

    private var upcomingCount: Int { calendarStore.todayUpcomingCount }
    private var questsCount:   Int { calendarStore.todayImportantCount }
    private var focusMinutes:  Int { focusStore.totalTodayMinutes }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY'S SUMMARY")
                .font(Bocil.header(16))
                .foregroundColor(Bocil.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            summaryRow(
                icon:   "calendar",
                value:  upcomingCount == 0 ? "0" : "\(upcomingCount)",
                label:  upcomingCount == 0 ? "nothing scary yet"
                        : upcomingCount == 1 ? "upcoming event" : "upcoming events",
                sub:    upcomingCount == 0 ? "" : minsUntilNextText,
                empty:  upcomingCount == 0,
                action: onOpenCalendar
            )
            Rectangle().fill(Bocil.hairline).frame(height: 1)
            summaryRow(
                icon:   "checkmark.square",
                value:  questsCount == 0 ? "0" : "\(questsCount)",
                label:  questsCount == 0 ? "looks pretty chill"
                        : questsCount == 1 ? "tiny quest" : "tiny quests",
                sub:    questsCount == 0 ? "" : "due today",
                empty:  questsCount == 0,
                action: onOpenCalendar
            )
            Rectangle().fill(Bocil.hairline).frame(height: 1)
            summaryRow(
                icon:   "clock",
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
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
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
                if !sub.isEmpty {
                    Text(sub)
                        .font(Bocil.mono(14))
                        .foregroundColor(Bocil.subtext)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    private var minsUntilNextText: String {
        guard let mins = calendarStore.minutesUntilNext() else { return "today" }
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
        .frame(width: 1100, height: 700)
}
