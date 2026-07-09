import Foundation
import Combine

// See PROFILE_API.md. Single-user profile: name, role, and today's focus total.
struct UserProfile: Codable {
    let name: String?
    let role: String?
    let focusSecondsToday: Int
    let date: String            // "YYYY-MM-DD", server-local
    let updatedAt: String?      // ISO 8601 UTC
}

@MainActor
final class ProfileBackendService: ObservableObject {
    @Published var profile: UserProfile?
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL = BackendConfig.baseURL
    private let deviceToken = BackendConfig.deviceToken

    /// `GET /api/v1/profile` — the server returns a default empty profile (not
    /// 404) when none exists, so a successful fetch always yields a `profile`.
    func fetchProfile() async {
        isLoading = true
        error = nil
        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/profile")!)
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkOKStatus(response, data: data)
            profile = try JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// `PATCH /api/v1/profile` — partial update; only the provided fields are
    /// sent. Returns true on success and stores the returned profile.
    @discardableResult
    func updateProfile(name: String?, role: String?) async -> Bool {
        do {
            var body: [String: String] = [:]
            if let name { body["name"] = name }
            if let role { body["role"] = role }

            var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/profile")!)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkOKStatus(response, data: data)
            profile = try JSONDecoder().decode(UserProfile.self, from: data)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// `POST /api/v1/profile/focus` — additive; call once per completed session
    /// with that session's seconds. No-op for a non-positive value.
    func addFocus(seconds: Int) async {
        guard seconds > 0 else { return }
        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/profile/focus")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            request.httpBody = try JSONSerialization.data(withJSONObject: ["seconds": seconds])

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkOKStatus(response, data: data)
            profile = try JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func checkOKStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "ProfileBackend", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}
