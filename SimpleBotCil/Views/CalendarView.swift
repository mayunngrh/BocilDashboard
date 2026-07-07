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
    @StateObject private var backendService = CalendarBackendService()
    @StateObject private var tasksService = TasksBackendService()

    @State private var displayedMonth = Date()
    @State private var selectedDate   = Date()
    @State private var showAddEvent   = false
    @State private var showAddTask    = false
    @State private var draft          = NewEventDraft()
    @State private var taskTitle      = ""

    @State private var events: [CalendarEvent] = []

    private var backendEventsForSelectedDate: [BackendCalendarEvent] {
        let cal = Calendar.current
        return backendService.events
            .filter { event in
                cal.isDate(event.startsAt, inSameDayAs: selectedDate)
            }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private var selectedDateEvents: [CalendarEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            leftColumn
                .frame(width: 200)

            centerColumn
                .frame(minWidth: 400, maxWidth: .infinity)

            rightPanel
                .frame(width: 280)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Bocil.bg)
        .overlay {
            if showAddEvent { addEventOverlay }
        }
        .overlay {
            if showAddTask { addTaskOverlay }
        }
        .onAppear {
            Task {
                let calendar = Calendar.current
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
                let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
                await backendService.fetchEvents(from: startOfMonth, to: endOfMonth)
                await tasksService.fetchTasks()
            }
        }
        .onChange(of: displayedMonth) { _, newMonth in
            Task {
                let calendar = Calendar.current
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: newMonth))!
                let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
                await backendService.fetchEvents(from: startOfMonth, to: endOfMonth)
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
                    if backendService.isLoading {
                        ProgressView().scaleEffect(0.6)
                    } else if backendService.error == nil {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                    }
                }

                if let error = backendService.error {
                    Text(error)
                        .font(Bocil.mono(10))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(backendService.events.count) events loaded")
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.subtext)
                }

                Button(action: refreshBackendEvents) {
                    Text("Refresh")
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
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
            .background(Color.white)

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            // Timeline view
            timelineView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private var timelineView: some View {
        let hours = Array(0...23)
        let hourHeight: CGFloat = 60
        let now = Date()
        let nowHour = Calendar.current.component(.hour, from: now)
        let nowMin = Calendar.current.component(.minute, from: now)
        let nowOffsetY = CGFloat(nowHour) * hourHeight + CGFloat(nowMin) / 60 * hourHeight

        return ScrollViewReader { scrollProxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            ZStack(alignment: .topLeading) {
                                // Hour background
                                Rectangle()
                                    .fill(Color.white)
                                    .border(Bocil.hairline, width: 1)

                                // Hour label
                                Text(String(format: "%02d:00", hour))
                                    .font(Bocil.mono(11))
                                    .foregroundColor(Bocil.subtext)
                                    .padding(.leading, 8)
                                    .padding(.top, 4)

                                // Events in this hour
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(eventsInHour(hour), id: \.id) { event in
                                        timelineEventBlock(event, hourHeight: hourHeight)
                                    }
                                }
                                .padding(.leading, 70)
                                .padding(.top, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: hourHeight)
                            .id("hour_\(hour)")
                        }
                    }

                    // "Now" indicator line (red)
                    HStack(spacing: 0) {
                        Text(String(format: "%02d:%02d", nowHour, nowMin))
                            .font(Bocil.mono(10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(3)

                        Rectangle()
                            .fill(Color.red)
                            .frame(height: 2)
                    }
                    .padding(.leading, 8)
                    .offset(y: nowOffsetY - 12)
                }
            }
            .frame(maxHeight: .infinity)
            .onAppear {
                scrollProxy.scrollTo("hour_\(max(0, nowHour - 2))", anchor: .top)
            }
        }
    }

    private func eventsInHour(_ hour: Int) -> [BackendCalendarEvent] {
        backendEventsForSelectedDate.filter { event in
            let eventHour = Calendar.current.component(.hour, from: event.startsAt)
            return eventHour == hour
        }
    }

    @ViewBuilder
    private func timelineEventBlock(_ event: BackendCalendarEvent, hourHeight: CGFloat) -> some View {
        let startHour = Calendar.current.component(.hour, from: event.startsAt)
        let startMin = Calendar.current.component(.minute, from: event.startsAt)
        let endHour = Calendar.current.component(.hour, from: event.endsAt)
        let endMin = Calendar.current.component(.minute, from: event.endsAt)

        let startTimeStr = String(format: "%02d:%02d", startHour, startMin)
        let endTimeStr = String(format: "%02d:%02d", endHour, endMin)

        let durationMins = Int(event.endsAt.timeIntervalSince(event.startsAt) / 60)
        let blockHeight = CGFloat(durationMins) / 60 * hourHeight

        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(Bocil.mono(12))
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)

            if !event.location.isEmpty {
                Text(event.location)
                    .font(Bocil.mono(10))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }

            Text(startTimeStr + " - " + endTimeStr)
                .font(Bocil.mono(9))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(blockHeight, 50))
        .background(Bocil.accent)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1))
        .cornerRadius(4)
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
    private func backendEventRow(_ event: BackendCalendarEvent) -> some View {
        let hour = Calendar.current.component(.hour, from: event.startsAt)
        let minute = Calendar.current.component(.minute, from: event.startsAt)
        let displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        let period = hour >= 12 ? "PM" : "AM"
        let timeStr = String(format: "%d:%02d %@", displayHour, minute, period)

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(timeStr)
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.ink)
            }
            .frame(width: 40)

            Rectangle()
                .fill(event.isImportant ? Color.red : Bocil.accent)
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
                Text("Backend")
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

    // MARK: - Right panel (Tasks)

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TASKS")
                    .font(Bocil.header(16))
                    .foregroundColor(Bocil.ink)
                Spacer()
                Button(action: { showAddTask = true }) {
                    HStack(spacing: 3) {
                        Text("+").font(Bocil.header(13)).foregroundColor(Bocil.ink)
                        Text("Add").font(Bocil.mono(11)).foregroundColor(Bocil.ink)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            if tasksService.isLoading {
                VStack(alignment: .center, spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading tasks...")
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.subtext)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else if tasksService.tasks.isEmpty {
                VStack(alignment: .center, spacing: 12) {
                    Text("No tasks")
                        .font(Bocil.mono(12))
                        .foregroundColor(Bocil.faint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(tasksService.tasks) { task in
                            taskRow(task)
                            Rectangle().fill(Bocil.hairline).frame(height: 1)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.white)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    @ViewBuilder
    private func taskRow(_ task: BackendTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: (task.completed ?? false) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor((task.completed ?? false) ? Bocil.accent : Bocil.subtext)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.ink)
                    .strikethrough(task.completed ?? false)
                    .lineLimit(2)

                if let due = task.due {
                    Text(due)
                        .font(Bocil.mono(9))
                        .foregroundColor(Bocil.subtext)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start Time").font(Bocil.mono(11)).foregroundColor(Bocil.subtext)
                        HStack(spacing: 8) {
                            TextField("9", text: $draft.startHourStr)
                                .textFieldStyle(.plain).font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                                .frame(width: 50)
                            Text(":").font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                            TextField("00", text: $draft.startMinStr)
                                .textFieldStyle(.plain).font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                                .frame(width: 50)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("End Time").font(Bocil.mono(11)).foregroundColor(Bocil.subtext)
                        HStack(spacing: 8) {
                            TextField("10", text: $draft.endHourStr)
                                .textFieldStyle(.plain).font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                                .frame(width: 50)
                            Text(":").font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                            TextField("00", text: $draft.endMinStr)
                                .textFieldStyle(.plain).font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                                .frame(width: 50)
                        }
                    }

                    HStack(spacing: 12) {
                        Text("Important").font(Bocil.mono(11)).foregroundColor(Bocil.subtext)
                        Spacer()
                        PixelToggle(isOn: $draft.isImportant)
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
        print("[CalendarView] Add Event button clicked")
        guard !draft.title.isEmpty else {
            print("[CalendarView] Add Event failed: title is empty")
            return
        }
        print("[CalendarView] commitEvent() starting for: \(draft.title)")

        Task {
            do {
                let formatter = ISO8601DateFormatter()
                let startUTC = formatter.string(from: draft.startDate)
                let endUTC = formatter.string(from: draft.endDate)

                print("[CalendarView] Start date local: \(draft.startDate)")
                print("[CalendarView] End date local: \(draft.endDate)")
                print("[CalendarView] Start date UTC: \(startUTC)")
                print("[CalendarView] End date UTC: \(endUTC)")

                let url = URL(string: "http://10.64.52.184:8080/api/v1/calendar/events")!
                print("[CalendarView] POST URL: \(url)")

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer O6k4xgaZBLhPHCbzsbZqiyFcPvM7LfsCrw7fdgjy4wWLW8urQ0ERSgWHoXTKDyB1", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 10

                let body: [String: Any] = [
                    "title": draft.title,
                    "startsAt": startUTC,
                    "endsAt": endUTC,
                    "location": draft.location,
                    "isImportant": draft.isImportant,
                    "notes": NSNull()
                ]

                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                if let bodyStr = String(data: request.httpBody ?? Data(), encoding: .utf8) {
                    print("[CalendarView] Request body: \(bodyStr)")
                }

                print("[CalendarView] Sending POST request...")
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    print("[CalendarView] Response is not HTTPURLResponse: \(response)")
                    return
                }

                print("[CalendarView] Response status code: \(http.statusCode)")

                if let respStr = String(data: data, encoding: .utf8) {
                    print("[CalendarView] Response body: \(respStr)")
                }

                guard (200...201).contains(http.statusCode) else {
                    print("[CalendarView] Add event failed with status \(http.statusCode)")
                    return
                }

                print("[CalendarView] Add event succeeded! Closing modal and refreshing...")

                DispatchQueue.main.async {
                    showAddEvent = false
                    draft = NewEventDraft()
                    Task {
                        let calendar = Calendar.current
                        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
                        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
                        print("[CalendarView] Refreshing calendar events...")
                        await backendService.fetchEvents(from: startOfMonth, to: endOfMonth)
                    }
                }
            } catch {
                print("[CalendarView] Add event error: \(error)")
                if let nsError = error as? NSError {
                    print("[CalendarView] Error domain: \(nsError.domain)")
                    print("[CalendarView] Error code: \(nsError.code)")
                    print("[CalendarView] Error userInfo: \(nsError.userInfo)")
                }
            }
        }
    }

    private func refreshBackendEvents() {
        Task {
            let calendar = Calendar.current
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
            await backendService.fetchEvents(from: startOfMonth, to: endOfMonth)
        }
    }

    private var addTaskOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { showAddTask = false }

            VStack(alignment: .leading, spacing: 16) {
                Text("ADD TASK")
                    .font(Bocil.header(18))
                    .foregroundColor(Bocil.ink)

                VStack(spacing: 10) {
                    formField(label: "Title", placeholder: "Task name", text: $taskTitle)
                }

                HStack(spacing: 10) {
                    Button("Cancel") { showAddTask = false }
                        .font(Bocil.mono(13)).foregroundColor(Bocil.subtext)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
                        .buttonStyle(.plain)

                    Button("Add") { commitTask() }
                        .font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(taskTitle.isEmpty ? Bocil.hairline : Bocil.accentSoft)
                        .buttonStyle(.plain)
                        .disabled(taskTitle.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 360)
            .background(Color.white)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
        }
    }

    private func commitTask() {
        print("[CalendarView] Add Task button clicked for: \(taskTitle)")
        guard !taskTitle.isEmpty else {
            print("[CalendarView] Task title is empty")
            return
        }

        Task {
            await tasksService.addTask(title: taskTitle)
            DispatchQueue.main.async {
                showAddTask = false
                taskTitle = ""
            }
        }
    }
}

#Preview {
    CalendarView()
        .frame(width: 1000, height: 700)
}
