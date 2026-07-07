import Foundation

// MARK: - Repository abstraction
//
// The ViewModel talks to `ConversationRepository`, never to a concrete data
// source, so previews/tests can inject `MockConversationRepository` while the
// running app uses `APIConversationRepository`.

protocol ConversationRepository {
    func fetchConversations() async throws -> [Conversation]
}

// MARK: - Errors

enum ConversationAPIError: LocalizedError {
    case unauthorized
    case notFound
    case serverUnavailable
    case network(String)
    case decoding(String)
    case unexpected(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Not authorized — check the device token."
        case .notFound:
            return "Conversation history not found."
        case .serverUnavailable:
            return "Companion server is unavailable. Is Postgres running?"
        case .network(let message):
            return "Couldn't reach the companion server (\(message))."
        case .decoding(let message):
            return "Couldn't read the server's response (\(message))."
        case .unexpected(let code):
            return "Unexpected server error (\(code))."
        }
    }
}

// MARK: - API implementation
//
// See CONVERSATION_HISTORY_API.md. Read-only: sessions, then per-session
// turn-grouped history (`/history`, not the raw `/messages` list) so tool
// calls and user/assistant pairing come straight from the server instead of
// being inferred client-side. Audio bytes are fetched separately (see
// `ConversationAudioPlayer`) only when a message is actually played.

final class APIConversationRepository: ConversationRepository {
    private let baseURL = "http://10.235.115.130:8080"
    private let deviceToken = "O6k4xgaZBLhPHCbzsbZqiyFcPvM7LfsCrw7fdgjy4wWLW8urQ0ERSgWHoXTKDyB1"

    private struct SessionDTO: Decodable {
        let id: String
        let startedAt: String
        let endedAt: String?
    }

    private struct SessionsResponseDTO: Decodable {
        let sessions: [SessionDTO]
    }

    private struct TurnMessageDTO: Decodable {
        let id: String
        let content: String
        let audioUrl: String?
        let createdAt: String
    }

    private struct ToolCallDTO: Decodable {
        let id: String
        let tool: String
        let action: String?
        let label: String
        let status: String
        let summary: String?
        let createdAt: String
    }

    private struct TurnDTO: Decodable {
        let turnId: String
        let user: TurnMessageDTO?
        let toolCalls: [ToolCallDTO]
        let assistant: TurnMessageDTO?
    }

    private struct HistoryResponseDTO: Decodable {
        let sessionId: String
        let turns: [TurnDTO]
    }

    func fetchConversations() async throws -> [Conversation] {
        let sessions = try await fetchSessions()
        var conversations: [Conversation] = []
        conversations.reserveCapacity(sessions.count)
        for session in sessions {
            let turns = try await fetchHistory(sessionId: session.id)
            conversations.append(makeConversation(session, turns))
        }
        return conversations
    }

    private func fetchSessions() async throws -> [SessionDTO] {
        var components = URLComponents(string: "\(baseURL)/api/v1/conversations")!
        components.queryItems = [URLQueryItem(name: "limit", value: "200")]
        let data = try await get(components.url!)
        do {
            return try JSONDecoder().decode(SessionsResponseDTO.self, from: data).sessions
        } catch {
            throw ConversationAPIError.decoding(error.localizedDescription)
        }
    }

    private func fetchHistory(sessionId: String) async throws -> [TurnDTO] {
        let url = URL(string: "\(baseURL)/api/v1/conversations/\(sessionId)/history?limit=200")!
        let data = try await get(url)
        do {
            return try JSONDecoder().decode(HistoryResponseDTO.self, from: data).turns
        } catch {
            throw ConversationAPIError.decoding(error.localizedDescription)
        }
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ConversationAPIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ConversationAPIError.network("no HTTP response")
        }
        switch http.statusCode {
        case 200: return data
        case 401: throw ConversationAPIError.unauthorized
        case 404: throw ConversationAPIError.notFound
        case 503: throw ConversationAPIError.serverUnavailable
        default: throw ConversationAPIError.unexpected(http.statusCode)
        }
    }

    private func makeConversation(_ session: SessionDTO, _ turnDTOs: [TurnDTO]) -> Conversation {
        let formatter = ISO8601DateFormatter()
        let startedAt = formatter.date(from: session.startedAt) ?? Date()
        let endedAt = session.endedAt.flatMap { formatter.date(from: $0) }
        let id = UUID(uuidString: session.id) ?? UUID()

        func makeMessage(_ dto: TurnMessageDTO, turnId: String, sender: MessageSender) -> VoiceMessage {
            VoiceMessage(
                id: dto.id,
                sessionId: session.id,
                turnId: turnId,
                sender: sender,
                content: dto.content,
                audioURL: dto.audioUrl.flatMap { URL(string: baseURL + $0) },
                timestamp: formatter.date(from: dto.createdAt) ?? startedAt
            )
        }

        let turns: [ConversationTurn] = turnDTOs.map { turn in
            ConversationTurn(
                turnId: turn.turnId,
                user: turn.user.map { makeMessage($0, turnId: turn.turnId, sender: .user) },
                toolCalls: turn.toolCalls.map { call in
                    ConversationToolCall(
                        id: call.id,
                        tool: call.tool,
                        action: call.action,
                        label: call.label,
                        status: call.status,
                        summary: call.summary,
                        createdAt: formatter.date(from: call.createdAt) ?? startedAt
                    )
                },
                assistant: turn.assistant.map { makeMessage($0, turnId: turn.turnId, sender: .llm) }
            )
        }

        return Conversation(id: id, createdAt: startedAt, endedAt: endedAt, turns: turns)
    }
}

// MARK: - Mock implementation
//
// Used by previews only — the running app defaults to `APIConversationRepository`.

final class MockConversationRepository: ConversationRepository {

    func fetchConversations() async -> [Conversation] {
        let cal = Calendar.current
        let now = Date()

        func day(_ offset: Int) -> Date {
            cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) ?? now
        }

        return [
            makeConversation(day: day(0), hour: 8, minute: 12, turnCount: 2, withToolCall: true),
            makeConversation(title: "Standup recap", day: day(0), hour: 10, minute: 5, turnCount: 3),
            makeConversation(day: day(0), hour: 14, minute: 33, turnCount: 1),
            makeConversation(day: day(-1), hour: 17, minute: 47, turnCount: 2, withToolCall: true),
            makeConversation(day: day(-1), hour: 21, minute: 2, turnCount: 2),
            makeConversation(day: day(-2), hour: 11, minute: 3, turnCount: 2),
            makeConversation(title: "Weekend planning", day: day(-3), hour: 9, minute: 20, turnCount: 3),
            makeConversation(day: day(-4), hour: 15, minute: 41, turnCount: 2),
            makeConversation(day: day(-5), hour: 13, minute: 12, turnCount: 2),
        ]
    }

    private func makeConversation(
        title: String? = nil,
        day: Date,
        hour: Int,
        minute: Int,
        turnCount: Int,
        withToolCall: Bool = false
    ) -> Conversation {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        let end = cal.date(byAdding: .minute, value: turnCount * 2, to: start) ?? start

        let sampleLines = [
            ("Hey, how's it going?", "Doing well, how can I help?"),
            ("Can you check my schedule for today?", "You have a standup at 9 and a design review at 2."),
            ("Thanks, remind me an hour before.", "Got it, I'll remind you at 1 PM."),
        ]

        let turns: [ConversationTurn] = (0..<turnCount).map { i in
            let turnId = "turn-\(i + 1)"
            let userTime = cal.date(byAdding: .minute, value: i * 2, to: start) ?? start
            let assistantTime = cal.date(byAdding: .minute, value: i * 2 + 1, to: start) ?? start
            let (userLine, assistantLine) = sampleLines[i % sampleLines.count]

            let toolCalls: [ConversationToolCall] = (withToolCall && i == 0) ? [
                ConversationToolCall(
                    id: "mock_tool_\(UUID().uuidString)",
                    tool: "calendar",
                    action: "list",
                    label: "list",
                    status: "success",
                    summary: "Found 2 event(s).",
                    createdAt: userTime
                )
            ] : []

            return ConversationTurn(
                turnId: turnId,
                user: VoiceMessage(
                    id: "mock_\(UUID().uuidString)", sessionId: "mock-session", turnId: turnId,
                    sender: .user, content: userLine,
                    audioURL: URL(string: "https://example.com/mock/\(UUID().uuidString).wav"),
                    timestamp: userTime
                ),
                toolCalls: toolCalls,
                assistant: VoiceMessage(
                    id: "mock_\(UUID().uuidString)", sessionId: "mock-session", turnId: turnId,
                    sender: .llm, content: assistantLine,
                    audioURL: URL(string: "https://example.com/mock/\(UUID().uuidString).wav"),
                    timestamp: assistantTime
                )
            )
        }

        return Conversation(createdAt: start, endedAt: end, title: title, turns: turns)
    }
}
