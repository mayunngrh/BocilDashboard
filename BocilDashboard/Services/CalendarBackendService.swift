import Foundation
import Combine

struct BackendCalendarEvent: Identifiable, Codable {
    let id: String
    let title: String
    let startsAt: Date
    let endsAt: Date
    let location: String
    let isImportant: Bool
    let notes: String?
}

struct BackendCalendarEventsResponse: Codable {
    let events: [BackendCalendarEvent]
}

@MainActor
final class CalendarBackendService: ObservableObject {
    @Published var events: [BackendCalendarEvent] = []
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL = BackendConfig.baseURL
    private let deviceToken = BackendConfig.deviceToken

    func fetchEvents(from: Date, to: Date) async {
        isLoading = true
        error = nil
        do {
            let formatter = ISO8601DateFormatter()
            let fromStr = formatter.string(from: from)
            let toStr = formatter.string(from: to)

            var components = URLComponents(string: "\(baseURL)/api/v1/calendar/events")!
            components.queryItems = [
                URLQueryItem(name: "from", value: fromStr),
                URLQueryItem(name: "to", value: toStr),
            ]

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkOKStatus(response, data: data)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(BackendCalendarEventsResponse.self, from: data)
            DispatchQueue.main.async {
                self.events = result.events
                self.isLoading = false
            }
            return
        } catch {
            DispatchQueue.main.async {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    /// Applies a reschedule to the local `events` array immediately (so a drag
    /// feels instant) and returns the pre-change snapshot for rollback. Call
    /// this synchronously on the main actor, then `persistTimeChange` to save.
    @discardableResult
    func applyLocalTimeChange(id: String, startsAt: Date, endsAt: Date) -> [BackendCalendarEvent] {
        let previous = events
        if let idx = events.firstIndex(where: { $0.id == id }) {
            let e = events[idx]
            events[idx] = BackendCalendarEvent(
                id: e.id, title: e.title, startsAt: startsAt, endsAt: endsAt,
                location: e.location, isImportant: e.isImportant, notes: e.notes
            )
        }
        return previous
    }

    /// Persists a reschedule via `PATCH /api/v1/calendar/events/{id}` (only the
    /// times change; title/location/etc. stay as-is). On failure, rolls the
    /// local `events` array back to `previous` and surfaces the error.
    func persistTimeChange(id: String, startsAt: Date, endsAt: Date, previous: [BackendCalendarEvent]) async {
        do {
            let iso = ISO8601DateFormatter()
            let url = URL(string: "\(baseURL)/api/v1/calendar/events/\(id)")!
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "startsAt": iso.string(from: startsAt),
                "endsAt": iso.string(from: endsAt),
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkOKStatus(response, data: data)
        } catch {
            self.events = previous
            self.error = error.localizedDescription
        }
    }

    private static func checkOKStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "CalendarBackend", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}
