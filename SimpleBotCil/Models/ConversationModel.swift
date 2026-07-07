import Foundation

// MARK: - Conversation domain models
//
// These models mirror what the backend is expected to return. For now they are
// populated by `MockConversationRepository`, but the shapes are intentionally
// backend-friendly so swapping in a real API later requires no UI changes.

/// Who sent a given voice message.
enum MessageSender {
    case user
    case llm
}

/// A single voice message inside a conversation.
/// The backend currently only returns voice (no text), so every message is audio.
struct VoiceMessage: Identifiable {
    let id: UUID
    let sender: MessageSender
    let audioURL: URL          // dummy for now; real playable URL once backend is wired
    let duration: TimeInterval // seconds
    let timestamp: Date

    init(
        id: UUID = UUID(),
        sender: MessageSender,
        audioURL: URL,
        duration: TimeInterval,
        timestamp: Date
    ) {
        self.id = id
        self.sender = sender
        self.audioURL = audioURL
        self.duration = duration
        self.timestamp = timestamp
    }

    /// "09:41" style caption shown under each bubble.
    var timeCaption: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: timestamp)
    }

    /// "0:42" style duration label shown inside the bubble.
    var durationLabel: String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A conversation between the user and the LLM, made up of voice messages.
struct Conversation: Identifiable {
    let id: UUID
    let createdAt: Date
    let messages: [VoiceMessage]
    /// User-assigned title. The backend only returns raw audio collections with
    /// no name, so this is `nil` until the user renames the conversation via
    /// Edit mode. Use `displayTitle` for anything shown on screen.
    var title: String?

    init(
        id: UUID = UUID(),
        createdAt: Date,
        title: String? = nil,
        messages: [VoiceMessage]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.messages = messages
    }

    /// Title shown in the UI: the user-assigned name, or a sensible
    /// date-based placeholder ("Voice chat · Jul 7") when unnamed.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Voice chat · \(f.string(from: createdAt))"
    }

    /// Combined length of every message in the conversation.
    var totalDuration: TimeInterval {
        messages.reduce(0) { $0 + $1.duration }
    }

    /// "1:15" style total-duration label for the list card.
    var durationLabel: String {
        let total = Int(totalDuration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "08:12 AM" style start time for the list card subtitle.
    var startTimeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f.string(from: createdAt)
    }
}
