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

    private let baseURL = "http://10.64.52.184:8080"
    private let deviceToken = "O6k4xgaZBLhPHCbzsbZqiyFcPvM7LfsCrw7fdgjy4wWLW8urQ0ERSgWHoXTKDyB1"

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

    private static func checkOKStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "CalendarBackend", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}
