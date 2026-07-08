import Foundation

// MARK: - Conversation domain models
//
// These mirror the Conversation History API's turn-grouped `/history` endpoint
// (see CONVERSATION_HISTORY_API.md). The API is read-only, so there is no
// per-message duration or waveform in the payload — duration is only knowable
// once a message's audio has actually been downloaded.

/// Who sent a given voice message.
enum MessageSender {
    case user
    case llm
}

/// A single voice message inside a conversation. The backend always returns a
/// transcript (`content`); audio is only present when it was actually saved
/// for that turn, hence `audioURL` being optional.
struct VoiceMessage: Identifiable {
    let id: String             // e.g. "cmsg_abc123"
    let sessionId: String
    let turnId: String         // pairs the user/assistant side of one turn
    let sender: MessageSender
    let content: String        // transcript text; "" if transcription failed
    let audioURL: URL?         // nil if no audio was captured for this message
    let timestamp: Date

    /// "09:41" style caption shown under each bubble.
    var timeCaption: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: timestamp)
    }
}

/// One sub-agent lookup (`tasks`, `calendar`, `web_search`) the model made
/// while forming its reply to a turn. `tool`/`status` are kept as raw strings
/// rather than a strict enum so an unrecognized future value degrades to the
/// chip's default look instead of failing to decode the whole turn.
struct ConversationToolCall: Identifiable {
    let id: String
    let tool: String
    let action: String?
    let label: String
    let status: String          // "success" | "error" | "duplicate"
    let summary: String?
    let createdAt: Date
}

/// One turn: the user's side, any tool calls the model made while answering,
/// and the assistant's reply. Either side can be `nil` (e.g. transcription
/// failed for that half of the turn).
struct ConversationTurn: Identifiable {
    let turnId: String
    let user: VoiceMessage?
    let toolCalls: [ConversationToolCall]
    let assistant: VoiceMessage?

    var id: String { turnId }
}

/// A conversation between the user and the LLM, made up of turns.
/// Maps 1:1 to a `VoiceSession` (one WebSocket connection).
struct Conversation: Identifiable {
    let id: UUID
    let createdAt: Date        // session.startedAt
    let endedAt: Date?         // session.endedAt; nil while the session is still live
    let voiceCount: Int        // number of voice turns in this session (from the backend)
    let turns: [ConversationTurn]
    /// User-assigned title. The API returns no name for a session, so this is
    /// `nil` until the user renames it via Edit mode. Renaming is local-only —
    /// the history API has no write endpoint, so it won't survive a reload.
    var title: String?

    init(
        id: UUID = UUID(),
        createdAt: Date,
        endedAt: Date? = nil,
        voiceCount: Int = 0,
        title: String? = nil,
        turns: [ConversationTurn]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.voiceCount = voiceCount
        self.title = title
        self.turns = turns
    }

    /// Title shown in the UI: the user-assigned name, or a sensible
    /// date-based placeholder ("Voice chat · Jul 7") when unnamed.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Voice chat · \(f.string(from: createdAt))"
    }

    /// Number of voice turns in this session — shown on the list card.
    /// Uses voiceCount from the backend (even when turns are not yet loaded).
    var messageCount: Int {
        voiceCount
    }

    /// "1:15" session length (endedAt − createdAt), or "Live" while ongoing.
    var durationLabel: String {
        guard let endedAt else { return "Live" }
        let total = Int(endedAt.timeIntervalSince(createdAt).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "08:12 AM" style start time for the list card subtitle.
    var startTimeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f.string(from: createdAt)
    }
}
