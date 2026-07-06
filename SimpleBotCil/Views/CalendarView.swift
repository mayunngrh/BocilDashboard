import SwiftUI

// MARK: - Calendar grid helper

private func daysInGrid(for month: Date) -> [CalendarDay] {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    let comps    = cal.dateComponents([.year, .month], from: month)
    let firstDay = cal.date(from: comps)!
    let range    = cal.range(of: .day, in: .month, for: firstDay)!
    let weekday  = cal.component(.weekday, from: firstDay)
    let offset   = (weekday - 2 + 7) % 7
    var days: [CalendarDay] = (0..<offset).map { _ in CalendarDay(day: 0, date: nil, isCurrentMonth: false) }
    for d in range {
        var dc = comps; dc.day = d
        let date = cal.date(from: dc)!
        days.append(CalendarDay(day: d, date: date, isCurrentMonth: true))
    }
    return days
}

private let weekLabels = ["M", "T", "W", "T", "F", "S", "S"]

// MARK: - CalendarView

struct CalendarView: View {
    @EnvironmentObject var googleService: GoogleCalendarService
    @State private var displayedMonth = Date()
    @State private var selectedDate   = Date()
    @State private var showAddEvent   = false
    @State private var draft          = NewEventDraft()

    @State private var events: [CalendarEvent] = [
        CalendarEvent(title: "Team Standup",   hour: 9,  minute: 0,  location: "Zoom",        duration: "30m"),
        CalendarEvent(title: "UI Review",       hour: 11, minute: 0,  location: "Design Room", duration: "1h"),
        CalendarEvent(title: "Design Critique", hour: 14, minute: 0,  location: "Figma call",  duration: "1h"),
        CalendarEvent(title: "Assignment Due",  hour: 17, minute: 0,  location: "",            duration: "", isImportant: true),
        CalendarEvent(title: "Personal Time",   hour: 19, minute: 30, location: "",            duration: "1h"),
    ]

    private var selectedDateEvents: [CalendarEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute }
    }

    private var googleEventsForSelectedDate: [GoogleCalendarEvent] {
        let cal = Calendar.current
        return googleService.events
            .filter { event in
                guard let date = event.startDate else { return false }
                return cal.isDate(date, inSameDayAs: selectedDate)
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            leftColumn
                .frame(width: 250)
            centerColumn
            Color.clear
                .frame(width: 340)
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            if showAddEvent { addEventOverlay }
        }
        .task {
            if googleService.oauth.isAuthenticated {
                await googleService.refreshData()
            }
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TODAY")
                    .font(Bocil.header(24))
                    .foregroundColor(Bocil.ink)
                Text(todayFormatted)
                    .font(Bocil.mono(11))
                    .foregroundColor(Bocil.subtext)
            }
            .padding(.bottom, 4)

            // Mini calendar card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Button(action: { shiftMonth(-1) }) {
                        Text("‹")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Bocil.ink)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(monthTitle)
                        .font(Bocil.header(11))
                        .foregroundColor(Bocil.ink)
                    Spacer()
                    Button(action: { shiftMonth(1) }) {
                        Text("›")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Bocil.ink)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 0) {
                    ForEach(Array(weekLabels.enumerated()), id: \.offset) { _, w in
                        Text(w)
                            .font(Bocil.mono(9))
                            .foregroundColor(Bocil.subtext)
                            .frame(maxWidth: .infinity)
                    }
                }

                let grid = daysInGrid(for: displayedMonth)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                    spacing: 2
                ) {
                    ForEach(Array(grid.enumerated()), id: \.offset) { _, day in
                        if day.day == 0 {
                            Color.clear.frame(height: 28)
                        } else {
                            dayCell(day)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))

            // Sync status card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SYNC STATUS")
                        .font(Bocil.header(11))
                        .foregroundColor(Bocil.ink)
                    Spacer()
                    if googleService.isLoading || googleService.oauth.isAuthenticating {
                        ProgressView().scaleEffect(0.6)
                    } else if googleService.oauth.isAuthenticated {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                    }
                }

                if let error = googleService.error {
                    Text(error)
                        .font(Bocil.mono(10))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if googleService.oauth.isAuthenticated {
                    Text("\(googleService.events.count) events · \(googleService.tasks.count) tasks synced")
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.subtext)
                } else {
                    Text("Connect and sync your events so Bocil can nudge you before meetings and read out today's agenda")
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: connectGoogle) {
                    Text(googleService.oauth.isAuthenticated ? "Refresh" : "Connect google calendar")
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.white)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private func dayCell(_ day: CalendarDay) -> some View {
        let cal        = Calendar.current
        let isToday    = day.date.map { cal.isDateInToday($0) }    ?? false
        let isSelected = day.date.map { cal.isDate($0, inSameDayAs: selectedDate) } ?? false
        let hasDot     = day.date.map { d in
            events.contains { cal.isDate($0.date, inSameDayAs: d) }
                || googleService.events.contains { ($0.startDate).map { cal.isDate($0, inSameDayAs: d) } ?? false }
        } ?? false

        Button(action: { if let d = day.date { selectedDate = d } }) {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(Bocil.mono(10))
                    .foregroundColor(isToday ? .white : Bocil.ink)
                    .frame(width: 22, height: 22)
                    .background(
                        isToday    ? Bocil.ink        :
                        isSelected ? Bocil.accentSoft : Color.clear
                    )
                Circle()
                    .fill(hasDot ? (isToday ? Color.white.opacity(0.9) : Bocil.subtext) : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Center column

    private var centerColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack {
                    Text(scheduleDateTitle)
                        .font(Bocil.header(16))
                        .foregroundColor(Bocil.ink)
                    Spacer()
                    Button(action: { draft = NewEventDraft(); showAddEvent = true }) {
                        HStack(spacing: 5) {
                            Text("+").font(Bocil.header(13)).foregroundColor(Bocil.ink)
                            Text("Add event").font(Bocil.mono(12)).foregroundColor(Bocil.ink)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Rectangle().fill(Bocil.hairline).frame(height: 1)

                if selectedDateEvents.isEmpty && googleEventsForSelectedDate.isEmpty {
                    VStack {
                        Spacer()
                        Text("No events for this day")
                            .font(Bocil.mono(13))
                            .foregroundColor(Bocil.faint)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 160)
                } else {
                    VStack(spacing: 8) {
                        ForEach(googleEventsForSelectedDate) { event in
                            googleEventRow(event)
                        }
                        ForEach(selectedDateEvents) { event in
                            eventRow(event)
                        }
                    }
                    .padding(14)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))

            Button(action: openGoogleCalendar) {
                HStack(spacing: 6) {
                    Text("Open in Google Calendar")
                        .font(Bocil.mono(12))
                        .foregroundColor(Bocil.subtext)
                    Text("↗").font(.system(size: 12)).foregroundColor(Bocil.subtext)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .overlay(Rectangle().stroke(Bocil.hairline, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(event.timeDisplay)
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.ink)
                Text(event.periodDisplay)
                    .font(Bocil.mono(9))
                    .foregroundColor(Bocil.subtext)
            }
            .frame(width: 40)

            Rectangle()
                .fill(event.isImportant ? Bocil.accent : Bocil.accentSoft)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(Bocil.mono(13))
                    .foregroundColor(Bocil.ink)
                if !event.location.isEmpty {
                    Text(event.location)
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.subtext)
                }
                if !event.duration.isEmpty {
                    Text(event.duration)
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.faint)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    @ViewBuilder
    private func googleEventRow(_ event: GoogleCalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(event.displayTime)
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.ink)
            }
            .frame(width: 40)

            Rectangle()
                .fill(Bocil.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle)
                    .font(Bocil.mono(13))
                    .foregroundColor(Bocil.ink)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.subtext)
                }
                Text("Google Calendar")
                    .font(Bocil.mono(10))
                    .foregroundColor(Bocil.faint)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    // MARK: - Add event overlay

    private var addEventOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { showAddEvent = false }

            VStack(alignment: .leading, spacing: 20) {
                Text("ADD EVENT")
                    .font(Bocil.header(18))
                    .foregroundColor(Bocil.ink)

                VStack(spacing: 10) {
                    formField(label: "Title",    placeholder: "Event name", text: $draft.title)
                    formField(label: "Location", placeholder: "Optional",   text: $draft.location)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hour").font(Bocil.mono(11)).foregroundColor(Bocil.subtext)
                            TextField("9", text: $draft.hourStr)
                                .textFieldStyle(.plain).font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                                .frame(width: 60)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Min").font(Bocil.mono(11)).foregroundColor(Bocil.subtext)
                            TextField("00", text: $draft.minuteStr)
                                .textFieldStyle(.plain).font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                                .frame(width: 60)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Duration").font(Bocil.mono(11)).foregroundColor(Bocil.subtext)
                            TextField("30m", text: $draft.duration)
                                .textFieldStyle(.plain).font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                                .frame(width: 80)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button("Cancel") { showAddEvent = false }
                        .font(Bocil.mono(13)).foregroundColor(Bocil.subtext)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                        .buttonStyle(.plain)

                    Button("Add") { commitEvent() }
                        .font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(draft.title.isEmpty ? Bocil.hairline : Bocil.accentSoft)
                        .buttonStyle(.plain)
                        .disabled(draft.title.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 360)
            .background(Color.white)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
        }
    }

    @ViewBuilder
    private func formField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Bocil.mono(11)).foregroundColor(Bocil.subtext)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
        }
    }

    // MARK: - Helpers

    private var todayFormatted: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, dd MMMM yyyy"
        return f.string(from: Date()).uppercased()
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth).uppercased()
    }

    private var scheduleDateTitle: String {
        if Calendar.current.isDateInToday(selectedDate) { return "TODAY'S SCHEDULE" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: selectedDate).uppercased()
    }

    private func shiftMonth(_ delta: Int) {
        var comps = DateComponents(); comps.month = delta
        if let d = Calendar.current.date(byAdding: comps, to: displayedMonth) { displayedMonth = d }
    }

    private func commitEvent() {
        guard !draft.title.isEmpty else { return }
        events.append(CalendarEvent(
            title:    draft.title,
            date:     selectedDate,
            hour:     draft.hour,
            minute:   draft.minute,
            location: draft.location,
            duration: draft.duration
        ))
        showAddEvent = false
    }

    private func connectGoogle() {
        Task {
            if googleService.oauth.isAuthenticated {
                await googleService.refreshData()
            } else {
                await googleService.connect()
            }
        }
    }

    private func openGoogleCalendar() {
        if let url = URL(string: "https://calendar.google.com") { NSWorkspace.shared.open(url) }
    }
}

#Preview {
    CalendarView()
        .environmentObject(GoogleCalendarService(oauth: try! GoogleOAuthManager(clientJSONPath: Bundle.main.path(forResource: "google_oauth_client", ofType: "json") ?? "")))
        .frame(width: 1000, height: 700)
}
