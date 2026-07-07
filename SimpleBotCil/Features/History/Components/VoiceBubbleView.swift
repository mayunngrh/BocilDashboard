import SwiftUI

/// A single chat-room voice message: play button, waveform, duration, transcript,
/// and a time caption. User messages align right (accent), LLM messages align left.
struct VoiceBubbleView: View {
    let message: VoiceMessage

    @StateObject private var audioPlayer = ConversationAudioPlayer()

    private var isUser: Bool { message.sender == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubble
                if let error = audioPlayer.errorMessage {
                    Text(error)
                        .font(Bocil.mono(10))
                        .foregroundColor(Bocil.danger)
                        .padding(.horizontal, 2)
                }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                playButton

                WaveformView(
                    bars: WaveformView.mockBars(seed: message.id.hashValue),
                    color: isUser ? Bocil.ink.opacity(0.55) : Bocil.cardBorder,
                    height: 22
                )

                if audioPlayer.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if let duration = audioPlayer.duration {
                    Text(formatDuration(duration))
                        .font(Bocil.mono(12))
                        .foregroundColor(isUser ? Bocil.ink : Bocil.subtext)
                }
            }

            if !message.content.isEmpty {
                Text(message.content)
                    .font(Bocil.mono(13))
                    .foregroundColor(isUser ? Bocil.ink : Bocil.ink)
            } else if message.audioURL != nil {
                Text("Transcription unavailable")
                    .font(Bocil.mono(11))
                    .italic()
                    .foregroundColor(isUser ? Bocil.ink.opacity(0.6) : Bocil.subtext)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isUser ? Bocil.accentSoft : Color.white)
        .overlay(Rectangle().stroke(borderColor, lineWidth: 2))
    }

    @ViewBuilder
    private var playButton: some View {
        if let audioURL = message.audioURL {
            Button(action: { audioPlayer.toggle(url: audioURL) }) {
                Text(audioPlayer.isPlaying ? "❚❚" : "▶")
                    .font(.system(size: 11))
                    .foregroundColor(isUser ? Bocil.ink : Bocil.accent)
                    .frame(width: 30, height: 30)
                    .background(isUser ? Color.white.opacity(0.6) : Bocil.bg)
                    .overlay(Rectangle().stroke(borderColor, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        } else {
            Text("—")
                .font(.system(size: 11))
                .foregroundColor(Bocil.faint)
                .frame(width: 30, height: 30)
                .background(isUser ? Color.white.opacity(0.3) : Bocil.bg.opacity(0.5))
                .overlay(Rectangle().stroke(borderColor, lineWidth: 1.5))
        }
    }

    private var borderColor: Color {
        isUser ? Bocil.accentSoft : Bocil.cardBorder
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    VStack(spacing: 16) {
        VoiceBubbleView(message: VoiceMessage(
            id: "cmsg_1", sessionId: "s1", turnId: "turn-1",
            sender: .user, content: "Hey, how's it going?",
            audioURL: URL(string: "https://example.com/a.wav"),
            timestamp: Date()
        ))
        VoiceBubbleView(message: VoiceMessage(
            id: "cmsg_2", sessionId: "s1", turnId: "turn-1",
            sender: .llm, content: "Doing well, how can I help?",
            audioURL: URL(string: "https://example.com/b.wav"),
            timestamp: Date()
        ))
    }
    .padding()
    .frame(width: 500)
    .background(Bocil.bg)
}
