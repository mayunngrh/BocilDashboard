import Foundation

// MARK: - Repository abstraction
//
// The ViewModel talks to `ConversationRepository`, never to a concrete data
// source. To connect the real backend later, add an `APIConversationRepository`
// that implements this protocol and inject it into `HistoryViewModel` — no View
// or ViewModel changes required.

protocol ConversationRepository {
    func fetchConversations() async -> [Conversation]
}

// MARK: - Mock implementation
//
// ⚠️ THIS is where all hardcoded conversation data lives. Replace this type with
// a networked implementation once the backend is available.

final class MockConversationRepository: ConversationRepository {

    func fetchConversations() async -> [Conversation] {
        let cal = Calendar.current
        let now = Date()

        // Anchor days relative to "now" so the grouped view always has fresh
        // "Today" / "Yesterday" / weekday buckets regardless of run date.
        func day(_ offset: Int) -> Date {
            cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) ?? now
        }

        return [
            // ---- Today (multiple) ----
            makeConversation(
                title: "Morning check-in",
                day: day(0), hour: 8, minute: 12,
                messageCount: 4
            ),
            makeConversation(
                title: "Standup recap",
                day: day(0), hour: 10, minute: 5,
                messageCount: 6
            ),
            makeConversation(
                title: "Quick question",
                day: day(0), hour: 14, minute: 33,
                messageCount: 2
            ),

            // ---- Yesterday (multiple) ----
            makeConversation(
                title: "Focus session wrap-up",
                day: day(-1), hour: 17, minute: 47,
                messageCount: 5
            ),
            makeConversation(
                title: "Evening reflection",
                day: day(-1), hour: 21, minute: 2,
                messageCount: 3
            ),

            // ---- Older days within the current week ----
            makeConversation(
                title: "Untitled chat",
                day: day(-2), hour: 11, minute: 3,
                messageCount: 4
            ),
            makeConversation(
                title: "Weekend planning",
                day: day(-3), hour: 9, minute: 20,
                messageCount: 6
            ),
            makeConversation(
                title: "Idea dump",
                day: day(-4), hour: 15, minute: 41,
                messageCount: 3
            ),
            makeConversation(
                title: "Retro notes",
                day: day(-5), hour: 13, minute: 12,
                messageCount: 4
            ),
        ]
    }

    // MARK: - Mock builders

    /// Builds a conversation with alternating user/LLM voice messages, each spaced
    /// a minute apart so the chat timeline reads naturally.
    private func makeConversation(
        title: String,
        day: Date,
        hour: Int,
        minute: Int,
        messageCount: Int
    ) -> Conversation {
        let cal = Calendar.current
        let start = cal.date(
            bySettingHour: hour, minute: minute, second: 0, of: day
        ) ?? day

        // Deterministic pseudo-random durations so previews stay stable.
        let durations: [TimeInterval] = [4, 7, 3, 9, 5, 6, 8, 2]

        let messages: [VoiceMessage] = (0..<messageCount).map { i in
            let sender: MessageSender = (i % 2 == 0) ? .user : .llm
            let timestamp = cal.date(byAdding: .minute, value: i, to: start) ?? start
            return VoiceMessage(
                sender: sender,
                audioURL: URL(string: "https://example.com/mock/\(UUID().uuidString).m4a")!,
                duration: durations[i % durations.count],
                timestamp: timestamp
            )
        }

        return Conversation(createdAt: start, title: title, messages: messages)
    }
}
