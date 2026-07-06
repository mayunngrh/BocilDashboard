//
//  SpeechManager.swift
//  SimpleBotCil
//

import Foundation
import Speech
import AVFoundation
import AppKit
import Combine

enum VoiceState {
    case idle           // listening for wake word
    case awake          // heard wake word, listening for command
    case processing     // parsing command
}

@MainActor
final class SpeechManager: NSObject, ObservableObject {
    @Published var voiceState: VoiceState = .idle
    @Published var lastTranscript: String = ""
    @Published var statusMessage: String = "Listening for \"Hey BotCil\"..."
    @Published var isAvailable: Bool = false

    var onCommand: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()

    private var commandTimeoutTask: Task<Void, Never>?
    private static let wakeWords = ["hey botcil", "hey bot sill", "hey bot seal", "hey bot cil"]

    override init() {
        super.init()
        checkExistingPermissions()
    }

    // MARK: - Permissions

    private func checkExistingPermissions() {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVAudioApplication.shared.recordPermission
        print("🎤 Speech status: \(speechStatus.rawValue), Mic status: \(micStatus.rawValue)")

        if speechStatus == .authorized && micStatus == .granted {
            isAvailable = true
            startListening()
        } else {
            // Not authorized yet (notDetermined OR denied) — show the enable button
            // so the user can trigger the request or be guided to Settings.
            statusMessage = "needs_enable"
        }
    }

    func requestPermissions() {
        // If already permanently denied, sending another request does nothing —
        // the user must go to Settings. Detect that and route there.
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVAudioApplication.shared.recordPermission
        if speechStatus == .denied || micStatus == .denied {
            statusMessage = "mic_denied"
            return
        }

        statusMessage = "Requesting permissions..."
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                print("🎤 Speech auth returned: \(status.rawValue)")
                guard status == .authorized else {
                    self.statusMessage = "mic_denied"
                    return
                }
                let micGranted = await AVAudioApplication.requestRecordPermission()
                print("🎤 Mic granted: \(micGranted)")
                if micGranted {
                    self.isAvailable = true
                    self.startListening()
                } else {
                    self.statusMessage = "mic_denied"
                }
            }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Recognition Loop

    func startListening() {
        guard isAvailable else { return }
        stopRecognition()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            statusMessage = "Audio engine failed: \(error.localizedDescription)"
            return
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let transcript = result.bestTranscription.formattedString.lowercased()
                    self.lastTranscript = transcript
                    self.handleTranscript(transcript)
                }
                if error != nil || (result?.isFinal == true) {
                    // Restart the loop unless we're in processing state
                    if self.voiceState != .processing {
                        self.startListening()
                    }
                }
            }
        }
    }

    private func handleTranscript(_ transcript: String) {
        switch voiceState {
        case .idle:
            let detected = Self.wakeWords.contains(where: { transcript.contains($0) })
            if detected {
                enterAwakeState()
            }

        case .awake:
            // Wait for a meaningful command (more than just the wake word)
            let cleaned = stripWakeWord(from: transcript)
            if cleaned.count > 3 {
                commandTimeoutTask?.cancel()
                scheduleCommandTimeout()
                // Only process on what looks like a final segment (silence-based heuristic:
                // transcript stops growing — we rely on restart-on-final below)
            }

        case .processing:
            break
        }
    }

    private func enterAwakeState() {
        voiceState = .awake
        statusMessage = "Listening... say your command"
        speak("Yes?")
        // Restart fresh so we get a clean transcript for the command
        stopRecognition()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.startCommandListening()
        }
    }

    private func startCommandListening() {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch { return }

        scheduleCommandTimeout()

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.lastTranscript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    if self.voiceState == .awake {
                        let command = self.lastTranscript
                        self.processCommand(command)
                    }
                }
            }
        }
    }

    private func scheduleCommandTimeout() {
        commandTimeoutTask?.cancel()
        commandTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s silence timeout
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                if self.voiceState == .awake {
                    let command = self.lastTranscript
                    self.processCommand(command)
                }
            }
        }
    }

    private func processCommand(_ raw: String) {
        commandTimeoutTask?.cancel()
        guard voiceState == .awake else { return }
        voiceState = .processing
        statusMessage = "Processing: \"\(raw)\""

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            speak("I didn't catch that. Try again.")
            resetToIdle()
        } else {
            onCommand?(trimmed)
        }
    }

    func resetToIdle() {
        voiceState = .idle
        statusMessage = "Listening for \"Hey BotCil\"..."
        lastTranscript = ""
        startListening()
    }

    // MARK: - Helpers

    private func stripWakeWord(from text: String) -> String {
        var result = text
        for w in Self.wakeWords {
            result = result.replacingOccurrences(of: w, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.1
        synthesizer.speak(utterance)
    }

    private func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    deinit {
        commandTimeoutTask?.cancel()
    }
}
