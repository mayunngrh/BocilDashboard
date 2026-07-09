import Foundation
import Combine

struct GoogleCalendarEvent: Identifiable, Codable {
    let id: String
    let summary: String?
    let start: EventDateTime?
    let end: EventDateTime?
    let location: String?
    let description: String?

    struct EventDateTime: Codable {
        let dateTime: String?
        let date: String?
        let timeZone: String?
    }

    var displayTitle: String { summary ?? "No Title" }

    var startDate: Date? {
        guard let dateStr = start?.dateTime ?? start?.date else { return nil }
        if let d = ISO8601DateFormatter().date(from: dateStr) { return d }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return dayFormatter.date(from: dateStr)
    }

    var displayTime: String {
        if let dateTime = start?.dateTime, let date = ISO8601DateFormatter().date(from: dateTime) {
            let f = DateFormatter()
            f.timeStyle = .short
            return f.string(from: date)
        }
        return start?.date ?? ""
    }
}

struct GoogleTask: Identifiable, Codable {
    let id: String
    let title: String
    let due: String?
    let completed: Bool?
    let notes: String?
}

@MainActor
final class GoogleCalendarService: ObservableObject {
    @Published var events: [GoogleCalendarEvent] = []
    @Published var tasks: [GoogleTask] = []
    @Published var isLoading = false
    @Published var error: String?

    let oauth: GoogleOAuthManager

    init(oauth: GoogleOAuthManager) {
        self.oauth = oauth
    }

    /// Triggers the one-time interactive login, then loads data on success.
    func connect() async {
        do {
            _ = try await oauth.getAccessToken()
            await refreshData()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshData() async {
        isLoading = true
        error = nil
        do {
            async let fetchedEvents = fetchCalendarEvents()
            async let fetchedTasks = fetchTasks()
            let (events, tasks) = try await (fetchedEvents, fetchedTasks)
            self.events = events
            self.tasks = tasks
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func fetchCalendarEvents() async throws -> [GoogleCalendarEvent] {
        let token = try await oauth.getAccessToken()

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "maxResults", value: "20"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "timeMin", value: ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date())))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOKStatus(response, data: data)

        struct Response: Codable { let items: [GoogleCalendarEvent]? }
        return try JSONDecoder().decode(Response.self, from: data).items ?? []
    }

    private func fetchTasks() async throws -> [GoogleTask] {
        let token = try await oauth.getAccessToken()

        let url = URL(string: "https://www.googleapis.com/tasks/v1/lists/@default/tasks?showCompleted=true")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOKStatus(response, data: data)

        struct Response: Codable { let items: [GoogleTask]? }
        return try JSONDecoder().decode(Response.self, from: data).items ?? []
    }

    private static func checkOKStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "GoogleCalendar", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}
