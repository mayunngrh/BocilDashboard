import SwiftUI

/// Chat-room style detail for a single conversation. Renders every voice message
/// as a bubble (`VoiceBubbleView`), aligned by sender. Reached by tapping a row
/// in `HistoryView`; `onBack` returns to the list.
struct ConversationDetailView: View {
    let conversation: Conversation
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(conversation.messages) { message in
                        VoiceBubbleView(message: message)
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
                    .background(Color.white)
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
        .background(Color.white)
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
            title: "Morning check-in",
            messages: [
                VoiceMessage(sender: .user, audioURL: URL(string: "https://x/a.m4a")!, duration: 5, timestamp: Date()),
                VoiceMessage(sender: .llm, audioURL: URL(string: "https://x/b.m4a")!, duration: 8, timestamp: Date()),
                VoiceMessage(sender: .user, audioURL: URL(string: "https://x/c.m4a")!, duration: 3, timestamp: Date()),
            ]
        ),
        onBack: {}
    )
    .frame(width: 1000, height: 700)
    .background(Bocil.bg)
}
