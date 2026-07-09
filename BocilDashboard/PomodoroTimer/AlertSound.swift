//
//  AlertSound.swift
//  BocilDashboard
//

import AVFoundation

class AlertSound {
    static let shared = AlertSound()

    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()

    // 8-bit victory jingle: C5 E5 G5 E5 C6
    private let notes: [(freq: Float, duration: Float)] = [
        (523.25, 0.10),  // C5
        (659.25, 0.10),  // E5
        (783.99, 0.10),  // G5
        (659.25, 0.08),  // E5
        (1046.5, 0.30),  // C6 — held
        (0,      0.05),  // rest
        (1046.5, 0.15),  // C6 — accent
        (0,      0.04),  // rest
        (1046.5, 0.20),  // C6 — final
    ]

    func play() {
        // Tear down previous engine if running
        engine.stop()
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        let sampleRate: Double = 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2 as AVAudioChannelCount)!

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            print("AlertSound engine start error: \(error)")
            return
        }

        playerNode.play()

        scheduleJingle(sampleRate: sampleRate, format: format)
    }

    private func scheduleJingle(sampleRate: Double, format: AVAudioFormat) {
        for note in notes {
            let frameCount = AVAudioFrameCount(Double(note.duration) * sampleRate)
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { continue }
            buf.frameLength = frameCount

            let freq = note.freq
            let left  = buf.floatChannelData![0]
            let right = buf.floatChannelData![1]

            if freq == 0 {
                // silence
                for i in 0..<Int(frameCount) {
                    left[i] = 0
                    right[i] = 0
                }
            } else {
                for i in 0..<Int(frameCount) {
                    let t = Float(i) / Float(sampleRate)
                    // Square wave (8-bit style) with fast decay envelope
                    let raw = sinf(2 * .pi * freq * t) >= 0 ? Float(1.0) : Float(-1.0)
                    let envelope = max(0, 1.0 - t / note.duration * 0.6)
                    let sample = raw * envelope * 0.35
                    left[i]  = sample
                    right[i] = sample
                }
            }

            playerNode.scheduleBuffer(buf, completionHandler: nil)
        }

        // Loop: reschedule after jingle finishes
        let totalDuration = notes.reduce(0) { $0 + Double($1.duration) }
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            guard let self, self.engine.isRunning else { return }
            self.scheduleJingle(sampleRate: sampleRate, format: format)
        }
    }

    func stop() {
        playerNode.stop()
        engine.stop()
    }
}
