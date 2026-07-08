import SwiftUI

/// Chat-room style detail for a single conversation. Renders each turn as a
/// user bubble, any tool-call chips, then the assistant's reply bubble.
/// Reached by tapping a row in `HistoryView`; `onBack` returns to the list.
struct ConversationDetailView: View {
    let conversation: Conversation
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(conversation.turns) { turn in
                        if let user = turn.user {
                            VoiceBubbleView(message: user)
                        }
                        ForEach(turn.toolCalls) { call in
                            HStack {
                                ToolCallChipView(call: call)
                                Spacer(minLength: 60)
                            }
                        }
                        if let assistant = turn.assistant {
                            VoiceBubbleView(message: assistant)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Text("‹ Back")
                    .font(Bocil.mono(14))
                    .foregroundColor(Bocil.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Bocil.surface)
                    .overlay(Rectangle().stroke(Bocil.cardBorder, lineWidth: 2))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.displayTitle)
                    .font(Bocil.header(20))
                    .foregroundColor(Bocil.ink)
                Text(dateSubtitle)
                    .font(Bocil.mono(12))
                    .foregroundColor(Bocil.subtext)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
        .background(Bocil.surface)
        .overlay(Rectangle().fill(Bocil.hairline).frame(height: 1), alignment: .bottom)
    }

    private var dateSubtitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d · hh:mm a"
        return f.string(from: conversation.createdAt)
    }
}

#Preview {
    ConversationDetailView(
        conversation: Conversation(
            createdAt: Date(),
            endedAt: Date().addingTimeInterval(180),
            title: "Morning check-in",
            turns: [
                ConversationTurn(
                    turnId: "turn-1",
                    user: VoiceMessage(id: "cmsg_1", sessionId: "s1", turnId: "turn-1", sender: .user, content: "Hey, how's it going?", audioURL: URL(string: "https://x/a.wav"), timestamp: Date()),
                    toolCalls: [],
                    assistant: VoiceMessage(id: "cmsg_2", sessionId: "s1", turnId: "turn-1", sender: .llm, content: "Doing well, how can I help?", audioURL: URL(string: "https://x/b.wav"), timestamp: Date())
                ),
                ConversationTurn(
                    turnId: "turn-2",
                    user: VoiceMessage(id: "cmsg_3", sessionId: "s1", turnId: "turn-2", sender: .user, content: "What's on my calendar today?", audioURL: URL(string: "https://x/c.wav"), timestamp: Date()),
                    toolCalls: [
                        ConversationToolCall(id: "ctool_1", tool: "calendar", action: "list", label: "list", status: "success", summary: "Found 2 event(s).", createdAt: Date())
                    ],
                    assistant: VoiceMessage(id: "cmsg_4", sessionId: "s1", turnId: "turn-2", sender: .llm, content: "You have a standup at 9 and lunch at noon.", audioURL: URL(string: "https://x/d.wav"), timestamp: Date())
                ),
            ]
        ),
        onBack: {}
    )
    .frame(width: 1000, height: 700)
    .background(Bocil.bg)
}
