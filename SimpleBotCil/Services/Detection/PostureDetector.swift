//
//  PostureDetector.swift
//  SimpleBotCil
//

import Vision
import CoreImage
import Combine

enum Posture: String {
    case sitting = "Sitting"
    case standing = "Standing"
}

@MainActor
final class PostureDetector: ObservableObject {
    @Published var currentPosture: Posture?
    @Published var isCalibrated = false

    @Published var currentDuration: TimeInterval = 0
    @Published var totalSittingTime: TimeInterval = 0
    @Published var totalStandingTime: TimeInterval = 0

    // Debug metrics for live threshold calibration.
    @Published var debugShoulderY: CGFloat?
    @Published var debugShoulderDelta: CGFloat?
    @Published var debugFaceHeight: CGFloat?
    @Published var debugFaceDelta: CGFloat?
    @Published var debugHipL: CGFloat = 0
    @Published var debugHipR: CGFloat = 0

    private let sequenceHandler = VNSequenceRequestHandler()
    private var isProcessing = false

    // Primary signal thresholds.
    private let hipConfidenceThreshold: VNConfidence = 0.3
    private let standingDelta: CGFloat = 0.06
    private let faceHeightStandingDelta: CGFloat = 0.08

    // Calibration & baseline.
    private var baselineShoulderY: CGFloat?
    private var baselineFaceHeight: CGFloat?
    private var calibrationSamples: [CGFloat] = []
    private let calibrationSampleCount = 30
    private let baselineAlpha: CGFloat = 0.05 // Exponential moving average for rolling calibration.

    // Time-based state machine: sustained condition to switch posture.
    private var candidateSince: Date?
    private var notPostureSince: Date?
    private let postureChangeSustain: TimeInterval = 2.0
    private let flickerGrace: TimeInterval = 0.5
    private let exitGrace: TimeInterval = 2.0

    // Away detection: pause clock when no body detected.
    private var lastBodySeen: Date?
    private let awayThreshold: TimeInterval = 3.0
    private var wasAway = false

    // Track duration in current posture.
    private var postureStartTime: Date?
    private var pausedTime: TimeInterval = 0
    private var displayTimer: Timer?

    func process(pixelBuffer: CVPixelBuffer) {
        guard !isProcessing else { return }
        isProcessing = true

        let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            guard let self else { return }
            let results = request.results as? [VNHumanBodyPoseObservation]
            Task { @MainActor in
                self.handle(results: results)
                self.isProcessing = false
            }
        }

        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            isProcessing = false
        }
    }

    func recalibrate() {
        baselineShoulderY = nil
        baselineFaceHeight = nil
        calibrationSamples.removeAll()
        isCalibrated = false
        currentPosture = nil
        postureStartTime = nil
        currentDuration = 0
        totalSittingTime = 0
        totalStandingTime = 0
        candidateSince = nil
        notPostureSince = nil
        pausedTime = 0
        lastBodySeen = nil
        wasAway = false
        stopDurationTimer()
    }

    private func startDurationTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let startTime = self.postureStartTime else { return }
                let elapsed = Date().timeIntervalSince(startTime) - self.pausedTime
                self.currentDuration = max(0, elapsed)
            }
        }
    }

    private func stopDurationTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func handle(results: [VNHumanBodyPoseObservation]?) {
        guard let body = results?.first,
              let points = try? body.recognizedPoints(.all) else {
            // No body detected.
            lastBodySeen = nil
            return
        }

        lastBodySeen = Date()

        // Check if we were away and just came back.
        if wasAway, let startTime = postureStartTime {
            pausedTime += Date().timeIntervalSince(lastBodySeen ?? startTime)
            wasAway = false
        }

        // --- Signal 1: Hip visibility ---
        let leftHipConf = points[.leftHip]?.confidence ?? 0
        let rightHipConf = points[.rightHip]?.confidence ?? 0
        let bothHipsVisible = leftHipConf > hipConfidenceThreshold && rightHipConf > hipConfidenceThreshold
        debugHipL = CGFloat(leftHipConf)
        debugHipR = CGFloat(rightHipConf)

        // --- Signal 2: Shoulder-Y shift from baseline ---
        let shoulderY = averageShoulderY(points)
        debugShoulderY = shoulderY
        var shoulderSignal = false
        if let baseline = baselineShoulderY, let shoulderY {
            let delta = shoulderY - baseline
            shoulderSignal = delta > standingDelta
            debugShoulderDelta = delta
        }

        // --- Signal 3: Face height & scale (from face observation if available) ---
        var faceSignal = false
        if let faceObs = points[.nose], faceObs.confidence > 0.3,
           let leftEye = points[.leftEye], leftEye.confidence > 0.3,
           let rightEye = points[.rightEye], rightEye.confidence > 0.3 {
            let faceHeight = abs(faceObs.location.y - (leftEye.location.y + rightEye.location.y) / 2)
            debugFaceHeight = faceHeight
            if let baseline = baselineFaceHeight {
                let delta = baseline - faceHeight  // Positive = face smaller/higher (standing)
                faceSignal = delta > faceHeightStandingDelta
                debugFaceDelta = delta
            }
        }

        // --- Calibration phase ---
        if baselineShoulderY == nil || baselineFaceHeight == nil {
            if let shoulderY, !bothHipsVisible {
                calibrationSamples.append(shoulderY)
                if calibrationSamples.count >= calibrationSampleCount {
                    baselineShoulderY = calibrationSamples.reduce(0, +) / CGFloat(calibrationSamples.count)
                    if let nose = points[.nose], nose.confidence > 0.3,
                       let leftEye = points[.leftEye], leftEye.confidence > 0.3,
                       let rightEye = points[.rightEye], rightEye.confidence > 0.3 {
                        baselineFaceHeight = abs(nose.location.y - (leftEye.location.y + rightEye.location.y) / 2)
                    }
                    isCalibrated = true
                    print("Posture calibrated. Baseline shoulderY = \(baselineShoulderY!)")
                }
            }
            return
        }

        // --- Rolling baseline adaptation (while sitting) ---
        if let baseline = baselineShoulderY, let shoulderY, !bothHipsVisible && !shoulderSignal {
            baselineShoulderY = baseline * (1 - baselineAlpha) + shoulderY * baselineAlpha
        }
        if let baseline = baselineFaceHeight, !bothHipsVisible && !faceSignal {
            if let nose = points[.nose], nose.confidence > 0.3,
               let leftEye = points[.leftEye], leftEye.confidence > 0.3,
               let rightEye = points[.rightEye], rightEye.confidence > 0.3 {
                let faceHeight = abs(nose.location.y - (leftEye.location.y + rightEye.location.y) / 2)
                baselineFaceHeight = baseline * (1 - baselineAlpha) + faceHeight * baselineAlpha
            }
        }

        // --- Decision: 2 of 3 signals required for standing ---
        let standingSignals = [bothHipsVisible, shoulderSignal, faceSignal].filter { $0 }.count
        let instantStanding = standingSignals >= 2

        updateStateMachine(instantStanding: instantStanding)
    }

    private func updateStateMachine(instantStanding: Bool) {
        let now = Date()

        // Check if away (no body detected for 3s).
        if let lastSeen = lastBodySeen {
            if now.timeIntervalSince(lastSeen) >= awayThreshold && !wasAway {
                wasAway = true
                pausedTime = 0
            }
        }

        if instantStanding {
            if candidateSince == nil {
                candidateSince = now
            }
            notPostureSince = nil
        } else {
            if notPostureSince == nil {
                notPostureSince = now
            }
            if let falseSince = notPostureSince, now.timeIntervalSince(falseSince) >= flickerGrace {
                candidateSince = nil
            }
        }

        if currentPosture == nil {
            // Initial entry: wait for standing sustained.
            if let since = candidateSince, now.timeIntervalSince(since) >= postureChangeSustain {
                currentPosture = .standing
                postureStartTime = now
                pausedTime = 0
                notPostureSince = nil
                startDurationTimer()
            } else if candidateSince == nil && !instantStanding {
                // No standing signal, default to sitting.
                if currentPosture != .sitting {
                    currentPosture = .sitting
                    postureStartTime = now
                    pausedTime = 0
                    startDurationTimer()
                }
            }
        } else if currentPosture == .sitting {
            if let since = candidateSince, now.timeIntervalSince(since) >= postureChangeSustain {
                currentPosture = .standing
                totalSittingTime += Date().timeIntervalSince(postureStartTime ?? now) - pausedTime
                postureStartTime = now
                pausedTime = 0
                notPostureSince = nil
                startDurationTimer()
            }
        } else if currentPosture == .standing {
            if !instantStanding {
                if notPostureSince == nil {
                    notPostureSince = now
                }
                if let since = notPostureSince, now.timeIntervalSince(since) >= exitGrace {
                    currentPosture = .sitting
                    totalStandingTime += Date().timeIntervalSince(postureStartTime ?? now) - pausedTime
                    postureStartTime = now
                    pausedTime = 0
                    candidateSince = nil
                    startDurationTimer()
                }
            } else {
                notPostureSince = nil
            }
        }
    }

    private func averageShoulderY(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> CGFloat? {
        let left = points[.leftShoulder]
        let right = points[.rightShoulder]

        var ys: [CGFloat] = []
        if let left, left.confidence > 0.3 { ys.append(left.location.y) }
        if let right, right.confidence > 0.3 { ys.append(right.location.y) }

        if ys.isEmpty, let nose = points[.nose], nose.confidence > 0.3 {
            ys.append(nose.location.y)
        }

        guard !ys.isEmpty else { return nil }
        return ys.reduce(0, +) / CGFloat(ys.count)
    }
}
