import Foundation
import Combine

// GET /api/v1/personas → { "active": "minion" | null, "available": [...] }
struct PersonasListResponse: Codable {
    let active: String?
    let available: [String]
}

// GET/PUT /api/v1/personas/{name} → { "name", "content", "active" }
struct PersonaDetail: Codable {
    let name: String
    let content: String
    let active: Bool
}

@MainActor
final class PersonaBackendService: ObservableObject {
    @Published var active: String?
    @Published var available: [String] = []
    @Published var isLoading = false
    @Published var error: String?

    private var baseURL: String { BackendConfig.baseURL }
    private let deviceToken = BackendConfig.deviceToken

    /// Name rule shared with the editor UI: letters, numbers, `-`, `_` only.
    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }

    /// Content rule: non-empty (not whitespace-only), max 64 KB.
    static func isValidContent(_ content: String) -> Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.utf8.count <= 64 * 1024
    }

    // MARK: - List (re-fetched every time the screen appears; the active
    // persona can change server-side via voice, so we never trust a cache).

    func fetchPersonas() async {
        isLoading = true
        error = nil
        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/personas")!)
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkOKStatus(response, data: data)

            let result = try JSONDecoder().decode(PersonasListResponse.self, from: data)
            active = result.active
            available = result.available
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Activate / clear (PUT /api/v1/personas with {"name": ...})

    /// Pass `nil` to clear back to the plain personality.
    func activate(_ name: String?) async {
        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/personas")!)
            request.httpMethod = "PUT"
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            // `name: null` must serialize as JSON null, so encode explicitly.
            let nameValue: Any = name ?? NSNull()
            request.httpBody = try JSONSerialization.data(withJSONObject: ["name": nameValue])

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkOKStatus(response, data: data)

            let result = try JSONDecoder().decode(PersonasListResponse.self, from: data)
            active = result.active
            available = result.available
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Editor: read one (GET /api/v1/personas/{name})

    func fetchDetail(_ name: String) async throws -> PersonaDetail {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/personas/\(name)")!)
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOKStatus(response, data: data)
        return try JSONDecoder().decode(PersonaDetail.self, from: data)
    }

    // MARK: - Editor: create or update (PUT /api/v1/personas/{name} with content)

    /// Same call creates a new character or overwrites an existing one.
    /// Returns the saved persona; `active == true` means the robot updates live
    /// on its next reply (drive the "saved — live on next reply" toast off this).
    @discardableResult
    func save(name: String, content: String) async throws -> PersonaDetail {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/personas/\(name)")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: ["content": content])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOKStatus(response, data: data)
        let saved = try JSONDecoder().decode(PersonaDetail.self, from: data)

        // Reflect a possible new name in the local list without a round-trip.
        if !available.contains(saved.name) { available.append(saved.name); available.sort() }
        if saved.active { active = saved.name }
        return saved
    }

    // MARK: - Editor: delete (DELETE /api/v1/personas/{name})

    /// Deleting the active persona clears it server-side; we mirror that locally.
    func delete(_ name: String) async {
        let previousAvailable = available
        let previousActive = active
        available.removeAll { $0 == name }
        if active == name { active = nil }

        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/api/v1/personas/\(name)")!)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkMutationStatus(response, data: data)
        } catch {
            available = previousAvailable
            active = previousActive
            self.error = error.localizedDescription
        }
    }

    private static func checkOKStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Self.error(from: response, data: data)
        }
    }

    private static func checkMutationStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...204).contains(http.statusCode) else {
            throw Self.error(from: response, data: data)
        }
    }

    /// Surfaces the server's `{"error":{"message":"…"}}` body when present, so
    /// validation failures (bad name / empty / too large) read clearly.
    private static func error(from response: URLResponse, data: Data) -> NSError {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        var message = String(data: data, encoding: .utf8) ?? "unknown error"
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any],
           let msg = err["message"] as? String {
            message = msg
        }
        return NSError(domain: "PersonaBackend", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
