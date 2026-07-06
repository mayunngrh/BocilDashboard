import SwiftUI

/// A single chat-room voice message: play button, duration, waveform, and a
/// time caption. User messages align right (accent), LLM messages align left.
struct VoiceBubbleView: View {
    let message: VoiceMessage

    @State private var isPlaying = false

    private var isUser: Bool { message.sender == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubble
                Text(message.timeCaption)
                    .font(Bocil.mono(11))
                    .foregroundColor(Bocil.faint)
                    .padding(.horizontal, 2)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    // MARK: - Bubble

    private var bubble: some View {
        HStack(spacing: 12) {
            Button(action: { isPlaying.toggle() }) {
                Text(isPlaying ? "❚❚" : "▶")
                    .font(.system(size: 11))
                    .foregroundColor(isUser ? Bocil.ink : Bocil.accent)
                    .frame(width: 30, height: 30)
                    .background(isUser ? Color.white.opacity(0.6) : Bocil.bg)
                    .overlay(Rectangle().stroke(borderColor, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            WaveformView(
                bars: WaveformView.mockBars(seed: message.id.hashValue),
                color: isUser ? Bocil.ink.opacity(0.55) : Bocil.cardBorder,
                height: 22
            )

            Text(message.durationLabel)
                .font(Bocil.mono(12))
                .foregroundColor(isUser ? Bocil.ink : Bocil.subtext)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isUser ? Bocil.accentSoft : Color.white)
        .overlay(Rectangle().stroke(borderColor, lineWidth: 2))
    }

    private var borderColor: Color {
        isUser ? Bocil.accentSoft : Bocil.cardBorder
    }
}

#Preview {
    VStack(spacing: 16) {
        VoiceBubbleView(message: VoiceMessage(
            sender: .user,
            audioURL: URL(string: "https://example.com/a.m4a")!,
            duration: 6, timestamp: Date()
        ))
        VoiceBubbleView(message: VoiceMessage(
            sender: .llm,
            audioURL: URL(string: "https://example.com/b.m4a")!,
            duration: 9, timestamp: Date()
        ))
    }
    .padding()
    .frame(width: 500)
    .background(Bocil.bg)
}
