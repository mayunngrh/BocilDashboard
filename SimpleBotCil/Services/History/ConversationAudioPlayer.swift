import AVFoundation
import Combine

/// Plays one voice message's audio. Owned per-bubble by `VoiceBubbleView`.
///
/// The history audio endpoint is authenticated (see CONVERSATION_HISTORY_API.md),
/// so playback always goes through a fetch-then-play step: download the WAV with
/// the bearer token, hand the bytes straight to `AVAudioPlayer(data:)`, and read
/// `duration` off the loaded player — the API has no duration field, so this is
/// the only point real duration becomes known.
@MainActor
final class ConversationAudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var duration: TimeInterval?
    @Published var errorMessage: String?

    private let deviceToken = "O6k4xgaZBLhPHCbzsbZqiyFcPvM7LfsCrw7fdgjy4wWLW8urQ0ERSgWHoXTKDyB1"
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        if isPlaying {
            pause()
        } else if let player {
            resume(player)
        } else {
            Task { await load(url: url) }
        }
    }

    private func load(url: URL) async {
        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: url)
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ConversationAPIError.network("no HTTP response")
            }
            guard http.statusCode == 200 else {
                throw http.statusCode == 401 ? ConversationAPIError.unauthorized
                    : http.statusCode == 404 ? ConversationAPIError.notFound
                    : ConversationAPIError.unexpected(http.statusCode)
            }

            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            self.player = player
            self.duration = player.duration
            isLoading = false
            resume(player)
        } catch let error as ConversationAPIError {
            isLoading = false
            errorMessage = error.errorDescription
        } catch {
            isLoading = false
            errorMessage = "Couldn't load audio (\(error.localizedDescription))."
        }
    }

    private func resume(_ player: AVAudioPlayer) {
        player.play()
        isPlaying = true
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }
}

extension ConversationAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}
