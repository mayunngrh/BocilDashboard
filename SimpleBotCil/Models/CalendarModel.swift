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
    var hourStr: String = "9"
    var minuteStr: String = "00"
    var duration: String = "30m"

    var hour: Int { Int(hourStr) ?? 9 }
    var minute: Int { Int(minuteStr) ?? 0 }
}
