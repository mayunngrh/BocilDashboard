import Foundation

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

    init(title: String, date: Date = Date(), hour: Int, minute: Int, location: String, duration: String, isImportant: Bool = false) {
        self.title = title
        self.date = date
        self.hour = hour
        self.minute = minute
        self.location = location
        self.duration = duration
        self.isImportant = isImportant
    }

    var timeDisplay: String {
        let isPM = hour >= 12
        let displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return String(format: "%d:%02d", displayHour, minute)
    }

    var periodDisplay: String {
        hour >= 12 ? "PM" : "AM"
    }
}

struct NewEventDraft {
    var title: String = ""
    var location: String = ""
    var startHourStr: String = "9"
    var startMinStr: String = "00"
    var endHourStr: String = "10"
    var endMinStr: String = "00"
    var isImportant: Bool = false

    var startDate: Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = Int(startHourStr) ?? 9
        comps.minute = Int(startMinStr) ?? 0
        comps.second = 0
        return cal.date(from: comps) ?? now
    }

    var endDate: Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = Int(endHourStr) ?? 10
        comps.minute = Int(endMinStr) ?? 0
        comps.second = 0
        return cal.date(from: comps) ?? now
    }
}
