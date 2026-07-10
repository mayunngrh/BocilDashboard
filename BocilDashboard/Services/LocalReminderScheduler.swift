import Foundation
import Combine
import UserNotifications

/// Schedules local reminder notifications for tasks/events, driven by
/// Settings' `notifications.*` (taskReminders, calendarAlerts,
/// remindBeforeMinutes — CONFIG_API.md). This gives working reminders on this
/// Mac immediately, independent of whether CompanionServer's APNs push is
/// configured (PUSH_API.md) — both paths post the same `companion` payload
/// shape, so AppDelegate's tap handler works for either.
///
/// "Queue" here is `UNUserNotificationCenter`'s own pending-request list —
/// every scheduled reminder sits there until it fires or is superseded by a
/// reschedule, and `queuedCount` mirrors its size for display in Settings.
@MainActor
final class LocalReminderScheduler: ObservableObject {
    static let shared = LocalReminderScheduler()

    @Published private(set) var queuedCount = 0

    private let taskPrefix = "bocil.reminder.task."
    private let eventPrefix = "bocil.reminder.event."

    private init() {}

    /// Clears every reminder this app previously queued and re-derives the
    /// full set from the given tasks/events plus the *current* notification
    /// settings (fetched fresh — never trusts a cache, same rule as the
    /// persona screen). Safe to call as often as task/event data changes.
    func reschedule(tasks: [BackendTask], events: [BackendCalendarEvent]) async {
        let center = UNUserNotificationCenter.current()

        let configService = ConfigBackendService()
        await configService.fetchConfig()
        let notif = configService.config?.notifications

        // Defaults match Settings' own @State defaults when config hasn't
        // loaded yet, so a slow/offline server doesn't silently drop reminders.
        let taskRemindersEnabled = notif?.taskReminders ?? true
        let calendarAlertsEnabled = notif?.calendarAlerts ?? true
        let remindBeforeMinutes = notif?.remindBeforeMinutes ?? 10
        let offset = TimeInterval(remindBeforeMinutes * 60)

        await clearQueued(center: center)

        var requests: [UNNotificationRequest] = []

        if taskRemindersEnabled {
            let isoFormatter = ISO8601DateFormatter()
            for task in tasks {
                guard task.completed != true,
                      let dueAtString = task.dueAt,
                      let dueAt = isoFormatter.date(from: dueAtString) else { continue }
                let fireDate = dueAt.addingTimeInterval(-offset)
                guard fireDate > Date() else { continue }

                requests.append(Self.makeRequest(
                    identifier: taskPrefix + task.id,
                    title: String(localized: "reminder.task.title"),
                    body: task.title,
                    fireDate: fireDate,
                    companion: ["type": "reminder", "kind": "task", "id": task.id, "title": task.title]
                ))
            }
        }

        if calendarAlertsEnabled {
            for event in events {
                let fireDate = event.startsAt.addingTimeInterval(-offset)
                guard fireDate > Date() else { continue }

                requests.append(Self.makeRequest(
                    identifier: eventPrefix + event.id,
                    title: String(localized: "reminder.event.title"),
                    body: event.title,
                    fireDate: fireDate,
                    companion: ["type": "reminder", "kind": "event", "id": event.id, "title": event.title]
                ))
            }
        }

        for request in requests {
            try? await center.add(request)
        }
        queuedCount = requests.count
    }

    /// Removes every pending reminder this app queued, without re-adding any.
    /// Used when a user turns both toggles off, or on sign-out-equivalent resets.
    func clearAll() async {
        await clearQueued(center: UNUserNotificationCenter.current())
        queuedCount = 0
    }

    private func clearQueued(center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter {
            $0.hasPrefix(taskPrefix) || $0.hasPrefix(eventPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    private static func makeRequest(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        companion: [String: Any]
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["companion": companion]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}
