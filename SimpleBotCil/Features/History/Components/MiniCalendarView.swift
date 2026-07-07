import SwiftUI

/// Compact month calendar styled after the mini calendar on the Calendar page.
/// Supports month («‹ ›») and year navigation; tapping a day calls `onSelect`.
/// Used by the History filter's "Pick date" dropdown.
struct MiniCalendarView: View {
    let selectedDate: Date?
    let onSelect: (Date) -> Void

    @State private var displayedMonth: Date

    init(selectedDate: Date?, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.onSelect = onSelect
        _displayedMonth = State(initialValue: selectedDate ?? Date())
    }

    private static let weekLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(spacing: 0) {
                ForEach(Array(Self.weekLabels.enumerated()), id: \.offset) { _, w in
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
                        Color.clear.frame(height: 24)
                    } else {
                        dayCell(day)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(Bocil.surface)
    }

    // MARK: - Header (month + year navigation)

    private var header: some View {
        HStack(spacing: 2) {
            navButton("«") { shift(.year, -1) }
            navButton("‹") { shift(.month, -1) }
            Spacer()
            Text(monthTitle)
                .font(Bocil.header(11))
                .foregroundColor(Bocil.ink)
            Spacer()
            navButton("›") { shift(.month, 1) }
            navButton("»") { shift(.year, 1) }
        }
    }

    private func navButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Bocil.ink)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day cell

    @ViewBuilder
    private func dayCell(_ day: CalendarDay) -> some View {
        let cal        = Calendar.current
        let isToday    = day.date.map { cal.isDateInToday($0) } ?? false
        let isSelected = day.date.flatMap { d in selectedDate.map { cal.isDate(d, inSameDayAs: $0) } } ?? false

        Button(action: { if let d = day.date { onSelect(d) } }) {
            Text("\(day.day)")
                .font(Bocil.mono(10))
                .foregroundColor(
                    isToday    ? Bocil.surface  :
                    isSelected ? Bocil.onAccent : Bocil.ink
                )
                .frame(width: 24, height: 24)
                .background(
                    isToday    ? Bocil.ink        :
                    isSelected ? Bocil.accentSoft : Color.clear
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth).uppercased()
    }

    private func shift(_ component: Calendar.Component, _ delta: Int) {
        if let d = Calendar.current.date(byAdding: component, value: delta, to: displayedMonth) {
            displayedMonth = d
        }
    }

    /// Monday-first month grid, matching the Calendar page layout.
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
}

#Preview {
    MiniCalendarView(selectedDate: Date()) { _ in }
        .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
        .padding()
        .background(Bocil.bg)
}
