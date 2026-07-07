import Foundation
import Combine

struct CalendarDay {
    let day: Int
    let date: Date?
    let isCurrentMonth: Bool
}

struct CalendarEvent: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let hour: Int
    let minute: Int
    let location: String
    let duration: String
    let isImportant: Bool

    init(title: String, date: Date = Date(), hour: Int, minute: Int,
         location: String, duration: String, isImportant: Bool = false) {
        self.title = title
        self.date = date
        self.hour = hour
        self.minute = minute
        self.location = location
        self.duration = duration
        self.isImportant = isImportant
    }

    var timeDisplay: String {
        let h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return String(format: "%d:%02d", h, minute)
    }

    var periodDisplay: String { hour >= 12 ? "PM" : "AM" }
}

struct NewEventDraft {
    var title: String = ""
    var location: String = ""
    var hourStr: String = "9"
    var minuteStr: String = "00"
    var duration: String = "30m"

    var hour: Int { Int(hourStr) ?? 9 }
    var minute: Int { Int(minuteStr) ?? 0 }
}

// MARK: - CalendarStore

final class CalendarStore: ObservableObject {
    @Published var events: [CalendarEvent] = [
        CalendarEvent(title: "Team Standup",   hour: 9,  minute: 0,  location: "Zoom",        duration: "30m"),
        CalendarEvent(title: "UI Review",       hour: 11, minute: 0,  location: "Design Room", duration: "1h"),
        CalendarEvent(title: "Design Critique", hour: 14, minute: 0,  location: "Figma call",  duration: "1h"),
        CalendarEvent(title: "Assignment Due",  hour: 17, minute: 0,  location: "",            duration: "", isImportant: true),
        CalendarEvent(title: "Personal Time",   hour: 19, minute: 30, location: "",            duration: "1h"),
    ]

    var todayEvents: [CalendarEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.date, inSameDayAs: Date()) }
            .sorted { $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute }
    }

    // Upcoming events that haven't started yet
    var todayUpcomingCount: Int {
        let now = Calendar.current
        let h = now.component(.hour, from: Date())
        let m = now.component(.minute, from: Date())
        return todayEvents.filter { $0.hour > h || ($0.hour == h && $0.minute > m) }.count
    }

    // Important events today (shown as "tiny quests")
    var todayImportantCount: Int {
        todayEvents.filter { $0.isImportant }.count
    }

    // Minutes until the next upcoming event
    func minutesUntilNext() -> Int? {
        let now = Calendar.current
        let h = now.component(.hour, from: Date())
        let m = now.component(.minute, from: Date())
        guard let next = todayEvents.first(where: { $0.hour > h || ($0.hour == h && $0.minute > m) }) else { return nil }
        return max(1, (next.hour * 60 + next.minute) - (h * 60 + m))
    }
}
