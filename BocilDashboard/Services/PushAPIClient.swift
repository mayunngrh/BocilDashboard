import Foundation

enum PushEnvironment: String, Codable {
    case sandbox
    case production
}

struct PushDevice: Decodable {
    let id: String
    let platform: String
    let deviceToken: String
    let bundleId: String
    let environment: PushEnvironment
    let updatedAt: Date
}

struct RegisterPushDeviceRequest: Encodable {
    let platform = "macos"
    let deviceToken: String
    let bundleId: String
    let environment: PushEnvironment
}

struct DeletePushDeviceRequest: Encodable {
    let deviceToken: String
}

@MainActor
final class PushAPIClient {
    private let baseURL: String
    private let deviceToken: String
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: String, deviceToken: String) {
        self.baseURL = baseURL
        self.deviceToken = deviceToken

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
    }

    func register(
        apnsDeviceToken: String,
        bundleId: String,
        environment: PushEnvironment
    ) async throws -> PushDevice {
        guard let url = URL(string: "\(baseURL)/api/v1/push/device") else {
            throw NSError(domain: "PushAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let payload = RegisterPushDeviceRequest(
            deviceToken: apnsDeviceToken,
            bundleId: bundleId,
            environment: environment
        )
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(
                domain: "PushAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "Register failed: \(body)"]
            )
        }

        return try decoder.decode(PushDevice.self, from: data)
    }

    func unregister(apnsDeviceToken: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/push/device") else {
            throw NSError(domain: "PushAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let payload = DeletePushDeviceRequest(deviceToken: apnsDeviceToken)
        request.httpBody = try encoder.encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (http.statusCode == 204 || http.statusCode == 404)
        else {
            throw NSError(
                domain: "PushAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "Unregister failed"]
            )
        }
    }
}
