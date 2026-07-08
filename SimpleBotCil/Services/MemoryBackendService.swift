import Foundation
import Combine

struct MemoryEntry: Identifiable, Codable {
    let id: String
    let content: String
    let source: String
    let createdAt: Date
}

struct MemoriesResponse: Codable {
    let memories: [MemoryEntry]
}

@MainActor
final class MemoryBackendService: ObservableObject {
    @Published var memories: [MemoryEntry] = []
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL = "http://10.235.115.130:8080"
    private let deviceToken = "O6k4xgaZBLhPHCbzsbZqiyFcPvM7LfsCrw7fdgjy4wWLW8urQ0ERSgWHoXTKDyB1"

    func fetchMemories() async {
        isLoading = true
        error = nil
        do {
            var components = URLComponents(string: "\(baseURL)/api/v1/memories")!
            components.queryItems = [URLQueryItem(name: "limit", value: "100")]

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkOKStatus(response, data: data)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let result = try decoder.decode(MemoriesResponse.self, from: data)
            memories = result.memories
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Deletes a single memory. Optimistic removal with rollback on failure.
    func deleteMemory(_ memory: MemoryEntry) async {
        let previous = memories
        memories.removeAll { $0.id == memory.id }

        do {
            let url = URL(string: "\(baseURL)/api/v1/memories/\(memory.id)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.checkMutationStatus(response, data: data)
        } catch {
            memories = previous
            self.error = error.localizedDescription
        }
    }

    /// There's no bulk-delete endpoint, so "clear all" fires the per-id
    /// DELETE for every currently-loaded memory.
    func clearAll() async {
        for memory in memories {
            await deleteMemory(memory)
        }
    }

    private static func checkOKStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "MemoryBackend", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }

    /// DELETE conventionally replies 204 (no body), unlike GET above.
    private static func checkMutationStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...204).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "MemoryBackend", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}
