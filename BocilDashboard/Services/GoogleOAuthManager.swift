import Foundation
import Combine
import AppKit
import Network
import Security

struct GoogleOAuthClient: Codable {
    let installed: Installed

    struct Installed: Codable {
        let client_id: String
        let client_secret: String
        let auth_uri: String
        let token_uri: String
        let redirect_uris: [String]
    }
}

@MainActor
final class GoogleOAuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var isAuthenticating = false
    @Published var lastError: String?

    private let client: GoogleOAuthClient.Installed
    private let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/tasks.readonly"
    ]
    private let keychainAccount = "google_oauth_refresh_token"
    private let keychainService = "com.bocil.BocilDashboard"

    private var accessToken: String?
    private var accessTokenExpiration: Date?

    init(clientJSONPath: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: clientJSONPath))
        let parsed = try JSONDecoder().decode(GoogleOAuthClient.self, from: data)
        self.client = parsed.installed
        super.init()
        self.isAuthenticated = (readRefreshToken() != nil)
    }

    /// Returns a valid access token, refreshing or triggering login as needed.
    func getAccessToken() async throws -> String {
        if let token = accessToken, let expiration = accessTokenExpiration, Date() < expiration {
            return token
        }

        if let refreshToken = readRefreshToken() {
            do {
                return try await refreshAccessToken(refreshToken: refreshToken)
            } catch {
                // Refresh token may have been revoked; fall through to interactive login.
                print("⚠️ Refresh failed, falling back to login: \(error)")
            }
        }

        return try await loginInteractively()
    }

    func signOut() {
        deleteRefreshToken()
        accessToken = nil
        accessTokenExpiration = nil
        isAuthenticated = false
    }

    // MARK: - Interactive login (one-time)

    private func loginInteractively() async throws -> String {
        isAuthenticating = true
        defer { isAuthenticating = false }

        let listener = try LoopbackListener()
        let port = listener.port

        var components = URLComponents(string: client.auth_uri)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: client.client_id),
            URLQueryItem(name: "redirect_uri", value: "http://localhost:\(port)"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        let authURL = components.url!

        NSWorkspace.shared.open(authURL)

        let code = try await listener.waitForCode()
        let tokens = try await exchangeCodeForTokens(code: code, redirectURI: "http://localhost:\(port)")

        if let refreshToken = tokens.refresh_token {
            saveRefreshToken(refreshToken)
        }

        self.accessToken = tokens.access_token
        self.accessTokenExpiration = Date().addingTimeInterval(tokens.expires_in - 60)
        self.isAuthenticated = true
        return tokens.access_token
    }

    private func exchangeCodeForTokens(code: String, redirectURI: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: client.token_uri)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: client.client_id),
            URLQueryItem(name: "client_secret", value: client.client_secret),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOKStatus(response, data: data)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - Silent refresh

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: client.token_uri)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: client.client_id),
            URLQueryItem(name: "client_secret", value: client.client_secret),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOKStatus(response, data: data)
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)

        self.accessToken = tokens.access_token
        self.accessTokenExpiration = Date().addingTimeInterval(tokens.expires_in - 60)
        self.isAuthenticated = true
        return tokens.access_token
    }

    private static func checkOKStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "GoogleOAuth", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
    }

    struct TokenResponse: Codable {
        let access_token: String
        let expires_in: TimeInterval
        let refresh_token: String?
        let token_type: String
    }

    // MARK: - Keychain persistence

    private func saveRefreshToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func readRefreshToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteRefreshToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// A one-shot local HTTP listener that captures the OAuth redirect on
/// `http://localhost:<port>` and extracts the `code` query parameter,
/// per Google's loopback-redirect flow for installed apps.
nonisolated private final class PortBox: @unchecked Sendable {
    var value: UInt16 = 0
}

nonisolated private final class LoopbackListener: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?
    private let queue = DispatchQueue(label: "com.bocil.oauth-loopback")

    init() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        let semaphore = DispatchSemaphore(value: 0)
        let portBox = PortBox()

        listener.stateUpdateHandler = { state in
            if case .ready = state, portBox.value == 0 {
                portBox.value = listener.port?.rawValue ?? 0
                semaphore.signal()
            }
        }
        listener.start(queue: queue)
        semaphore.wait()
        self.port = portBox.value
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var accumulated = buffer
            if let data = data { accumulated.append(data) }

            if let requestString = String(data: accumulated, encoding: .utf8),
               requestString.contains("\r\n\r\n") || requestString.contains("\n\n") {
                self.finish(requestString: requestString, connection: connection)
                return
            }

            if isComplete || error != nil {
                if let requestString = String(data: accumulated, encoding: .utf8) {
                    self.finish(requestString: requestString, connection: connection)
                }
                return
            }

            self.receive(on: connection, buffer: accumulated)
        }
    }

    private func finish(requestString: String, connection: NWConnection) {
        let responseBody = "<html><body><h3>You can close this tab and return to Bocil.</h3></body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(responseBody.utf8.count)\r\nConnection: close\r\n\r\n\(responseBody)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        guard let requestLine = requestString.split(separator: "\r\n").first ?? requestString.split(separator: "\n").first,
              let path = requestLine.split(separator: " ").dropFirst().first else {
            fail(NSError(domain: "GoogleOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Malformed redirect request"]))
            return
        }

        guard let url = URL(string: "http://localhost\(path)"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            fail(NSError(domain: "GoogleOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not parse redirect URL"]))
            return
        }

        if let errorParam = items.first(where: { $0.name == "error" })?.value {
            fail(NSError(domain: "GoogleOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Google denied access: \(errorParam)"]))
            return
        }

        guard let code = items.first(where: { $0.name == "code" })?.value else {
            fail(NSError(domain: "GoogleOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authorization code in redirect"]))
            return
        }

        listener.cancel()
        continuation?.resume(returning: code)
        continuation = nil
    }

    private func fail(_ error: Error) {
        listener.cancel()
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
