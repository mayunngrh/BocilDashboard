import Foundation
import Combine

struct NotificationsConfig: Codable {
    let taskReminders: Bool?
    let calendarAlerts: Bool?
    let remindBeforeMinutes: Int?
}

struct PrivacyConfig: Codable {
    let cameraAccess: Bool?
    let personalizationData: Bool?
}

// A subset of GET /api/v1/config — only the fields the app reads. Codable
// ignores `connection` — it's a hardcoded mock per CONFIG_API.md, nothing to
// read or write there.
struct AppConfig: Codable {
    let appearance: String?
    let personality: String?
    let language: String?
    let notifications: NotificationsConfig?
    let privacy: PrivacyConfig?
}

@MainActor
final class ConfigBackendService: ObservableObject {
    @Published var config: AppConfig?
    @Published var error: String?

    private var baseURL: String { BackendConfig.baseURL }
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

    /// Update notification settings — sends nested notifications object
    func updateNotifications(
        taskReminders: Bool? = nil,
        calendarAlerts: Bool? = nil,
        remindBeforeMinutes: Int? = nil
    ) async {
        var notif: [String: Any] = [:]
        if let taskReminders { notif["taskReminders"] = taskReminders }
        if let calendarAlerts { notif["calendarAlerts"] = calendarAlerts }
        if let remindBeforeMinutes { notif["remindBeforeMinutes"] = remindBeforeMinutes }

        await patchNested(["notifications": notif])
    }

    /// Update privacy settings. `personalizationData` also gates the AI's
    /// memory tool server-side (MEMORY_API.md) — toggling it here is what
    /// actually stops/resumes memory writes, not just a local UI flag.
    func updatePrivacy(
        cameraAccess: Bool? = nil,
        personalizationData: Bool? = nil
    ) async {
        var priv: [String: Any] = [:]
        if let cameraAccess { priv["cameraAccess"] = cameraAccess }
        if let personalizationData { priv["personalizationData"] = personalizationData }

        await patchNested(["privacy": priv])
    }

    /// `appearance` is `system` | `light` | `dark` — same enum as AppearanceMode.rawValue.
    func updateAppearance(_ value: String) async {
        await patch(["appearance": value])
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

    private func patchNested(_ fields: [String: Any]) async {
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
