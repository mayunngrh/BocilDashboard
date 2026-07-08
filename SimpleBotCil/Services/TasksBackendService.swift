import Foundation
import Combine

struct BackendTask: Identifiable, Codable {
    let id: String
    let title: String
    let dueAt: String?
    let completed: Bool?
    let notes: String?
}

struct BackendTasksResponse: Codable {
    let tasks: [BackendTask]?
}

@MainActor
final class TasksBackendService: ObservableObject {
    @Published var tasks: [BackendTask] = []
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL = "http://10.235.115.130:8080"
    private let deviceToken = "O6k4xgaZBLhPHCbzsbZqiyFcPvM7LfsCrw7fdgjy4wWLW8urQ0ERSgWHoXTKDyB1"

    func fetchTasks() async {
        isLoading = true
        error = nil
        print("[TasksBackendService] Fetching tasks from \(baseURL)/api/v1/tasks")
        do {
            let url = URL(string: "\(baseURL)/api/v1/tasks")!
            print("[TasksBackendService] URL: \(url)")

            var request = URLRequest(url: url)
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            print("[TasksBackendService] Sending GET request...")
            let (data, response) = try await URLSession.shared.data(for: request)

            print("[TasksBackendService] Response received")
            guard let http = response as? HTTPURLResponse else {
                print("[TasksBackendService] Response is not HTTPURLResponse")
                throw NSError(domain: "TasksBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            print("[TasksBackendService] Response status: \(http.statusCode)")
            if let respStr = String(data: data, encoding: .utf8) {
                print("[TasksBackendService] Response body: \(respStr)")
            }

            try Self.checkOKStatus(response, data: data)

            let decoder = JSONDecoder()
            let result = try decoder.decode(BackendTasksResponse.self, from: data)
            print("[TasksBackendService] Decoded \(result.tasks?.count ?? 0) tasks")

            DispatchQueue.main.async {
                self.tasks = result.tasks ?? []
                self.isLoading = false
                print("[TasksBackendService] Tasks updated on main thread")
            }
            return
        } catch {
            print("[TasksBackendService] Error: \(error)")
            DispatchQueue.main.async {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func addTask(title: String, dueAt: String? = nil, notes: String? = nil) async {
        print("[TasksBackendService] addTask() called with title: \(title)")
        do {
            let url = URL(string: "\(baseURL)/api/v1/tasks")!
            print("[TasksBackendService] POST URL: \(url)")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10

            let body: [String: Any?] = [
                "title": title,
                "dueAt": dueAt,
                "notes": notes
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 })

            if let bodyStr = String(data: request.httpBody ?? Data(), encoding: .utf8) {
                print("[TasksBackendService] Request body: \(bodyStr)")
            }

            print("[TasksBackendService] Sending POST request...")
            let (data, response) = try await URLSession.shared.data(for: request)

            print("[TasksBackendService] Response received")
            guard let http = response as? HTTPURLResponse else {
                print("[TasksBackendService] Response is not HTTPURLResponse")
                throw NSError(domain: "TasksBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            print("[TasksBackendService] Response status: \(http.statusCode)")
            if let respStr = String(data: data, encoding: .utf8) {
                print("[TasksBackendService] Response body: \(respStr)")
            }

            try Self.checkOKStatus(response, data: data)

            print("[TasksBackendService] Task added successfully")
            await fetchTasks()
        } catch {
            print("[TasksBackendService] Add task error: \(error)")
            if let nsError = error as? NSError {
                print("[TasksBackendService] Error domain: \(nsError.domain)")
                print("[TasksBackendService] Error code: \(nsError.code)")
            }
            DispatchQueue.main.async {
                self.error = error.localizedDescription
            }
        }
    }

    func toggleCompletion(_ task: BackendTask) async {
        let newValue = !(task.completed ?? false)
        print("[TasksBackendService] toggleCompletion(\(task.id)) -> \(newValue)")

        // Optimistic update so the checkbox responds immediately.
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = BackendTask(id: task.id, title: task.title, dueAt: task.dueAt, completed: newValue, notes: task.notes)
        }

        do {
            let url = URL(string: "\(baseURL)/api/v1/tasks/\(task.id)")!
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10
            request.httpBody = try JSONSerialization.data(withJSONObject: ["completed": newValue])

            let (data, response) = try await URLSession.shared.data(for: request)
            print("[TasksBackendService] toggleCompletion status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            try Self.checkMutationStatus(response, data: data)
            await fetchTasks()
        } catch {
            print("[TasksBackendService] toggleCompletion error: \(error)")
            // Revert the optimistic update and surface the failure.
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx] = task
            }
            self.error = error.localizedDescription
        }
    }

    func deleteTask(_ task: BackendTask) async {
        print("[TasksBackendService] deleteTask(\(task.id))")
        let previousTasks = tasks
        tasks.removeAll { $0.id == task.id }

        do {
            let url = URL(string: "\(baseURL)/api/v1/tasks/\(task.id)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            print("[TasksBackendService] deleteTask status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            try Self.checkMutationStatus(response, data: data)
        } catch {
            print("[TasksBackendService] deleteTask error: \(error)")
            tasks = previousTasks
            self.error = error.localizedDescription
        }
    }

    private static func checkOKStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "TasksBackend", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }

    /// PATCH/DELETE conventionally may reply 200 or 204 (no body), unlike the
    /// GET/POST endpoints above which always reply 200 with a JSON body.
    private static func checkMutationStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...204).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "TasksBackend", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }
}
