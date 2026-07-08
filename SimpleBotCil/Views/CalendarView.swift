import SwiftUI

// MARK: - Calendar grid helper

private func daysInGrid(for month: Date) -> [CalendarDay] {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
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
    @EnvironmentObject private var calendarStore: CalendarStore
    @StateObject private var backendService = CalendarBackendService()
    @StateObject private var tasksService = TasksBackendService()

    @State private var displayedMonth = Date()
    @State private var selectedDate   = Date()
    @State private var showAddEvent   = false
    @State private var showAddTask    = false
    @State private var draft          = NewEventDraft()
    @State private var taskTitle      = ""
    @State private var timelineWidth: CGFloat = 300
    @State private var selectedEvent: BackendCalendarEvent? = nil

    // Drag-to-reschedule state. `dragOffsetY` is snapped to the 15-minute grid.
    @State private var draggingEventID: String? = nil
    @State private var dragOffsetY: CGFloat = 0

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
        return calendarStore.events
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
        .overlay {
            if let event = selectedEvent { eventDetailOverlay(event) }
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
                        Image("ChevronLeftPixel")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
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
                        Image("ChevronRightPixel")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
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
            .background(Bocil.surface)
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
                        Rectangle().fill(Color.green).frame(width: 7, height: 7)
                    }
                }

                if let error = backendService.error {
                    Text(error)
                        .font(Bocil.mono(10))
                        .foregroundColor(Bocil.danger)
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
            .background(Bocil.surface)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private func dayCell(_ day: CalendarDay) -> some View {
        let cal        = Calendar.current
        let isToday    = day.date.map { cal.isDateInToday($0) }    ?? false
        let isSelected = day.date.map { cal.isDate($0, inSameDayAs: selectedDate) } ?? false
        let hasDot     = day.date.map { d in
            calendarStore.events.contains { cal.isDate($0.date, inSameDayAs: d) }
        } ?? false

        Button(action: { if let d = day.date { selectedDate = d } }) {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(Bocil.mono(10))
                    .foregroundColor(isToday ? Bocil.onAccent : Bocil.ink)
                    .frame(width: 22, height: 22)
                    .background(isToday ? Bocil.accentSoft : Color.clear)
                    .overlay {
                        if isSelected && !isToday {
                            Rectangle().stroke(Bocil.accentSoft, lineWidth: 1.5)
                        }
                    }
                Circle()
                    .fill(hasDot ? (isToday ? Bocil.onAccent : Bocil.subtext) : Color.clear)
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
            .background(Bocil.surface)

            Rectangle().fill(Bocil.hairline).frame(height: 1)

            // Timeline view
            timelineView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Bocil.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    private static let hourHeight: CGFloat = 60

    private var timelineView: some View {
        let hours = Array(0...23)
        let hourHeight = Self.hourHeight
        let gutter: CGFloat = 70
        let now = Date()
        let nowHour = Calendar.current.component(.hour, from: now)
        let nowMin = Calendar.current.component(.minute, from: now)
        let nowOffsetY = CGFloat(nowHour) * hourHeight + CGFloat(nowMin) / 60 * hourHeight
        let placements = Self.layoutPlacements(
            for: backendEventsForSelectedDate, hourHeight: hourHeight,
            availableWidth: max(timelineWidth - gutter - 8, 40)
        )

        return ScrollViewReader { scrollProxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Static hour grid (background lines + labels only).
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            ZStack(alignment: .topLeading) {
                                Rectangle()
                                    .fill(Bocil.surface)
                                    .border(Bocil.hairline, width: 1)

                                Text(String(format: "%02d:00", hour))
                                    .font(Bocil.mono(11))
                                    .foregroundColor(Bocil.subtext)
                                    .padding(.leading, 8)
                                    .padding(.top, 4)
                            }
                            .frame(height: hourHeight)
                            .id("hour_\(hour)")
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { timelineWidth = geo.size.width }
                                .onChange(of: geo.size.width) { _, newWidth in timelineWidth = newWidth }
                        }
                    )

                    // Events, absolutely positioned by actual start/end time so a
                    // multi-hour event spans hour rows correctly instead of being
                    // clipped inside a single hour's cell; overlapping events split
                    // into side-by-side columns instead of stacking on top of each other.
                    // Drag vertically to reschedule (snaps to 15-minute steps).
                    ForEach(placements) { placed in
                        let isDragging = draggingEventID == placed.event.id
                        timelineEventBlock(placed.event, height: placed.height)
                            .frame(width: placed.width, height: placed.height, alignment: .topLeading)
                            .clipped()
                            .overlay(alignment: .top) {
                                if isDragging { dragTimeBadge(placed.event) }
                            }
                            .opacity(isDragging ? 0.9 : 1)
                            .shadow(color: isDragging ? Color.black.opacity(0.25) : .clear, radius: 4, y: 2)
                            .contentShape(Rectangle())
                            .offset(
                                x: gutter + placed.xOffset,
                                y: placed.yOffset + (isDragging ? dragOffsetY : 0)
                            )
                            .zIndex(isDragging ? 1 : 0)
                            // One unified gesture avoids tap/drag arbitration
                            // ambiguity, and highPriority makes it win over the
                            // enclosing ScrollView's own drag handling. A release
                            // with no meaningful movement is treated as a tap.
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard abs(value.translation.height) >= 4 else { return }
                                        draggingEventID = placed.event.id
                                        dragOffsetY = Self.snapToGrid(value.translation.height, hourHeight: hourHeight)
                                    }
                                    .onEnded { value in
                                        defer { draggingEventID = nil; dragOffsetY = 0 }
                                        guard abs(value.translation.height) >= 4 else {
                                            selectedEvent = placed.event   // tap
                                            return
                                        }
                                        let snapped = Self.snapToGrid(value.translation.height, hourHeight: hourHeight)
                                        let deltaMinutes = Int((snapped / hourHeight * 60).rounded())
                                        reschedule(placed.event, byMinutes: deltaMinutes)
                                    }
                            )
                    }

                    // "Now" indicator line (red)
                    HStack(spacing: 0) {
                        Text(String(format: "%02d:%02d", nowHour, nowMin))
                            .font(Bocil.mono(10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Bocil.danger)

                        Rectangle()
                            .fill(Bocil.danger)
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

    // MARK: - Timeline event layout

    private struct TimelinePlacement: Identifiable {
        let id = UUID()
        let event: BackendCalendarEvent
        let yOffset: CGFloat
        let height: CGFloat
        let xOffset: CGFloat
        let width: CGFloat
    }

    /// Greedy column-packing layout (the same approach real calendar apps use):
    /// events are swept in start-time order; each joins the first column whose
    /// last event already ended, otherwise it opens a new column. Every event in
    /// a mutually-overlapping cluster shares that cluster's column count, so
    /// concurrent events render as side-by-side slices instead of overlapping.
    ///
    /// Bookkeeping is keyed by each span's index in the sorted array, not by
    /// `event.id` — recurring/synced calendar entries can share the same
    /// backend id across distinct occurrences, and keying a dictionary (or a
    /// SwiftUI `ForEach`) by that id would collide two unrelated events onto
    /// the same column/view identity.
    private static func layoutPlacements(
        for events: [BackendCalendarEvent], hourHeight: CGFloat, availableWidth: CGFloat
    ) -> [TimelinePlacement] {
        guard !events.isEmpty else { return [] }
        let cal = Calendar.current
        let columnGap: CGFloat = 8
        let verticalGap: CGFloat = 4

        struct Span { let event: BackendCalendarEvent; let startMin: Int; let endMin: Int }
        let spans = events.map { event -> Span in
            let startMin = cal.component(.hour, from: event.startsAt) * 60 + cal.component(.minute, from: event.startsAt)
            let rawEndMin = cal.component(.hour, from: event.endsAt) * 60 + cal.component(.minute, from: event.endsAt)
            let endMin = min(max(rawEndMin, startMin + 20), 24 * 60)
            return Span(event: event, startMin: startMin, endMin: endMin)
        }.sorted { $0.startMin < $1.startMin }

        var placements: [TimelinePlacement] = []
        var columnsEndMin: [Int] = []
        var columnOfIndex: [Int: Int] = [:]
        var clusterIndices: [Int] = []
        var clusterMaxEnd = 0

        func flushCluster() {
            guard !clusterIndices.isEmpty else { return }
            let columnCount = max(columnsEndMin.count, 1)
            let width = availableWidth / CGFloat(columnCount)
            for idx in clusterIndices {
                let span = spans[idx]
                let col = columnOfIndex[idx] ?? 0
                let rawHeight = CGFloat(span.endMin - span.startMin) / 60 * hourHeight
                placements.append(TimelinePlacement(
                    event: span.event,
                    yOffset: CGFloat(span.startMin) / 60 * hourHeight,
                    height: max(rawHeight - verticalGap, 26),
                    xOffset: CGFloat(col) * width,
                    width: max(width - columnGap, 40)
                ))
            }
            columnsEndMin = []
            columnOfIndex = [:]
            clusterIndices = []
            clusterMaxEnd = 0
        }

        for (i, span) in spans.enumerated() {
            if !clusterIndices.isEmpty && span.startMin >= clusterMaxEnd {
                flushCluster()
            }
            if let colIdx = columnsEndMin.firstIndex(where: { $0 <= span.startMin }) {
                columnsEndMin[colIdx] = span.endMin
                columnOfIndex[i] = colIdx
            } else {
                columnsEndMin.append(span.endMin)
                columnOfIndex[i] = columnsEndMin.count - 1
            }
            clusterIndices.append(i)
            clusterMaxEnd = max(clusterMaxEnd, span.endMin)
        }
        flushCluster()

        return placements
    }

    // MARK: - Timeline event block
    //
    // Styled after macOS Calendar's day-view chips: a solid color bar on the
    // leading edge, a translucent (50%) blue fill, and dark, readable text
    // rather than white-on-solid. Corners stay sharp, matching this app's
    // hard-edged boxes elsewhere.

    @ViewBuilder
    private func timelineEventBlock(_ event: BackendCalendarEvent, height: CGFloat) -> some View {
        let startHour = Calendar.current.component(.hour, from: event.startsAt)
        let startMin = Calendar.current.component(.minute, from: event.startsAt)
        let endHour = Calendar.current.component(.hour, from: event.endsAt)
        let endMin = Calendar.current.component(.minute, from: event.endsAt)
        let startTimeStr = String(format: "%02d:%02d", startHour, startMin)
        let endTimeStr = String(format: "%02d:%02d", endHour, endMin)

        // Short blocks can't fit all three lines without their text spilling into
        // the next event, so drop the secondary lines as the box shrinks.
        let showLocation = height >= 54 && !event.location.isEmpty
        let showTime = height >= 38

        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Bocil.accentSoft)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(Bocil.mono(12))
                    .fontWeight(.semibold)
                    .foregroundColor(Bocil.ink)
                    .lineLimit(height < 38 ? 1 : 2)

                if showLocation {
                    Text(event.location)
                        .font(Bocil.mono(10))
                        .foregroundColor(Bocil.subtext)
                        .lineLimit(1)
                }

                if showTime {
                    Text(startTimeStr + " - " + endTimeStr)
                        .font(Bocil.mono(9))
                        .foregroundColor(Bocil.subtext)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Bocil.accentSoft.opacity(0.5))
    }

    // MARK: - Drag-to-reschedule

    /// Small floating pill showing the event's live start time while dragging,
    /// so the user can see exactly where it will land before releasing.
    private func dragTimeBadge(_ event: BackendCalendarEvent) -> some View {
        let deltaMinutes = Int((dragOffsetY / Self.hourHeight * 60).rounded())
        let newStart = event.startsAt.addingTimeInterval(Double(deltaMinutes) * 60)
        return Text(Self.hourMinute(newStart))
            .font(Bocil.mono(10))
            .foregroundColor(Bocil.bg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Bocil.accent)
            .offset(y: -10)
    }

    private static func hourMinute(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Snaps a raw drag distance (points) to the nearest 15-minute step.
    private static func snapToGrid(_ dy: CGFloat, hourHeight: CGFloat) -> CGFloat {
        let stepPixels = hourHeight / 4   // 15 minutes
        return (dy / stepPixels).rounded() * stepPixels
    }

    /// Shifts an event by `deltaMinutes`, keeping its duration, clamping so it
    /// stays within the same day, then persists via the backend PATCH.
    private func reschedule(_ event: BackendCalendarEvent, byMinutes deltaMinutes: Int) {
        guard deltaMinutes != 0 else { return }
        let cal = Calendar.current
        let durationMin = Int(event.endsAt.timeIntervalSince(event.startsAt) / 60)
        let startMin = cal.component(.hour, from: event.startsAt) * 60 + cal.component(.minute, from: event.startsAt)

        // Clamp so the whole event stays inside 00:00–24:00 of its day.
        let newStartMin = min(max(startMin + deltaMinutes, 0), 24 * 60 - durationMin)
        let effectiveDelta = newStartMin - startMin
        guard effectiveDelta != 0 else { return }

        let newStart = event.startsAt.addingTimeInterval(Double(effectiveDelta) * 60)
        let newEnd = event.endsAt.addingTimeInterval(Double(effectiveDelta) * 60)

        // Apply locally first (synchronously, this frame) so the card stays put
        // at its new time instead of snapping back before the PATCH returns.
        let previous = backendService.applyLocalTimeChange(id: event.id, startsAt: newStart, endsAt: newEnd)
        Task {
            await backendService.persistTimeChange(id: event.id, startsAt: newStart, endsAt: newEnd, previous: previous)
        }
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
        .background(Bocil.surface)
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
                .fill(event.isImportant ? Bocil.danger : Bocil.accent)
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
            .background(Bocil.surface)
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
            } else if let error = tasksService.error {
                VStack(alignment: .center, spacing: 10) {
                    Text(error)
                        .font(Bocil.mono(11))
                        .foregroundColor(Bocil.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: { Task { await tasksService.fetchTasks() } }) {
                        Text("Retry")
                            .font(Bocil.mono(11))
                            .foregroundColor(Bocil.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay(Rectangle().stroke(Bocil.danger, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
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
        .background(Bocil.surface)
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.5))
    }

    @ViewBuilder
    private func taskRow(_ task: BackendTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: { Task { await tasksService.toggleCompletion(task) } }) {
                ZStack {
                    Rectangle()
                        .fill((task.completed ?? false) ? Bocil.ink : Color.clear)
                    Rectangle()
                        .stroke(Bocil.cardBorder, lineWidth: 1.5)
                    if task.completed ?? false {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Bocil.surface)
                    }
                }
                .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.ink)
                    .strikethrough(task.completed ?? false)
                    .lineLimit(2)

                if let due = task.dueAt {
                    Text(Self.formatTaskDue(due))
                        .font(Bocil.mono(9))
                        .foregroundColor(Bocil.subtext)
                }
            }
            Spacer()

            Button(action: { Task { await tasksService.deleteTask(task) } }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Bocil.faint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Add event overlay

    // MARK: - Event detail overlay
    //
    // Read-only detail popup shown when a timeline event card is tapped. The
    // backend exposes no update/delete endpoint for events (only GET + POST),
    // so this is view-only — there's nothing to edit or remove here yet.

    @ViewBuilder
    private func eventDetailOverlay(_ event: BackendCalendarEvent) -> some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { selectedEvent = nil }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle()
                        .fill(event.isImportant ? Color.red : Bocil.accentSoft)
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title)
                            .font(Bocil.header(18))
                            .foregroundColor(Bocil.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        if event.isImportant {
                            Text("IMPORTANT")
                                .font(Bocil.mono(10))
                                .foregroundColor(Color.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay(Rectangle().stroke(Color.red, lineWidth: 1))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(Bocil.hairline).frame(height: 1)

                detailRow(asset: "CalendarPixel", text: Self.eventDateLabel(event))
                detailRow(asset: "TimePixel", text: Self.eventTimeLabel(event))
                if !event.location.isEmpty {
                    detailRow(asset: "IconLocation", text: event.location)
                }
                if let notes = event.notes, !notes.isEmpty {
                    detailRow(asset: "ListPixel", text: notes)
                }

                HStack {
                    Spacer()
                    Button("Close") { selectedEvent = nil }
                        .font(Bocil.mono(13)).foregroundColor(Bocil.ink)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Bocil.accentSoft)
                        .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(width: 360)
            .background(Bocil.surface)
            .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
        }
    }

    @ViewBuilder
    private func detailRow(asset: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundColor(Bocil.subtext)
                .frame(width: 16, alignment: .center)
            Text(text)
                .font(Bocil.mono(13))
                .foregroundColor(Bocil.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private static func eventDateLabel(_ event: BackendCalendarEvent) -> String {
        let dayF = DateFormatter(); dayF.dateFormat = "EEE, MMM d"
        let cal = Calendar.current
        if cal.isDate(event.startsAt, inSameDayAs: event.endsAt) {
            return dayF.string(from: event.startsAt)
        }
        // Multi-day event: show both days.
        return "\(dayF.string(from: event.startsAt)) → \(dayF.string(from: event.endsAt))"
    }

    private static func eventTimeLabel(_ event: BackendCalendarEvent) -> String {
        let timeF = DateFormatter(); timeF.dateFormat = "HH:mm"
        return "\(timeF.string(from: event.startsAt)) – \(timeF.string(from: event.endsAt))  ·  \(eventDurationLabel(event))"
    }

    private static func eventDurationLabel(_ event: BackendCalendarEvent) -> String {
        let mins = Int(event.endsAt.timeIntervalSince(event.startsAt) / 60)
        let h = mins / 60, m = mins % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

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
            .background(Bocil.surface)
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

                let url = URL(string: "\(BackendConfig.baseURL)/api/v1/calendar/events")!
                print("[CalendarView] POST URL: \(url)")

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(BackendConfig.deviceToken)", forHTTPHeaderField: "Authorization")
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
            .background(Bocil.surface)
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

    /// "Jul 7, 11:00 AM" from the task's raw ISO 8601 `dueAt`; falls back to the
    /// raw string if it doesn't parse (defensive against a future format change).
    private static func formatTaskDue(_ dueAt: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dueAt) else { return dueAt }
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }
}

#Preview {
    CalendarView()
        .environmentObject(CalendarStore())
        .frame(width: 1000, height: 700)
}
