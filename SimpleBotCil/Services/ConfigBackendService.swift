import Foundation
import Combine

// A subset of GET /api/v1/config — only the fields the app reads. Codable
// ignores the rest (connection, notifications, privacy) until they're wired up.
struct AppConfig: Codable {
    let appearance: String?
    let personality: String?
    let language: String?
}

@MainActor
final class ConfigBackendService: ObservableObject {
    @Published var config: AppConfig?
    @Published var error: String?

    private let baseURL = BackendConfig.baseURL
    private let deviceToken = BackendConfig.deviceToken

    func fetchConfig() async {
        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/config")!)
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkOKStatus(response, data: data)
            config = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// `PATCH /api/v1/config` — partial update. Sends only the given key/value.
    func updatePersonality(_ value: String) async {
        await patch(["personality": value])
    }

    private func patch(_ fields: [String: String]) async {
        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/config")!)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            request.httpBody = try JSONSerialization.data(withJSONObject: fields)

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkOKStatus(response, data: data)
            config = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func checkOKStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "ConfigBackend", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}
