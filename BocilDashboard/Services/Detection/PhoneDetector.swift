//
//  PhoneDetector.swift
//  BocilDashboard
//

import Vision
import CoreImage
import Combine

enum PhoneDetectionMode: String {
    case twoHanded = "two-handed"
    case oneHanded = "one-handed"
}

@MainActor
final class PhoneDetector: ObservableObject {
    @Published var isPhoneDetected = false
    @Published var detectionMode: PhoneDetectionMode?
    @Published var currentDuration: TimeInterval = 0
    @Published var totalPhoneTime: TimeInterval = 0
    @Published var lastHandResults: [VNHumanHandPoseObservation] = []

    // Debug metrics for live threshold calibration (mirrors EmotionDetector.metrics).
    @Published var debugPitch: CGFloat?
    @Published var debugHandDist: CGFloat?
    @Published var debugGrip: Bool = false
    @Published var debugInZone: Bool = false

    private let sequenceHandler = VNSequenceRequestHandler()
    private var isProcessing = false

    // Gate: two hands close together (normalized coords).
    private let handCloseThreshold: CGFloat = 0.25
    private let handConfidence: VNConfidence = 0.3

    // Phone zone: hand must be below the face box, but not resting at desk
    // level (bottom of frame), and roughly centered under the face.
    private let zoneMinY: CGFloat = 0.05
    private let zoneHorizontalBand: CGFloat = 0.35

    // Confirmation: head pitched down while looking at the phone.
    private let pitchDownThreshold: CGFloat = 0.15  // radians, ~9deg

    // Confirmation: grip shape — fingers curled behind the phone are occluded.
    private let fingertipOccludedConfidence: VNConfidence = 0.3
    private let occludedFingertipsRequired = 2

    // Time-based state machine: sustained condition required to enter/exit,
    // so a moment of hands-together doesn't immediately flag as phone use.
    private var candidateSince: Date?
    private var candidateFalseSince: Date?
    private var notPhoneSince: Date?
    private let enterSustain: TimeInterval = 2.0
    private let flickerGrace: TimeInterval = 1.0
    private let exitGrace: TimeInterval = 2.0

    private var phoneStartTime: Date?
    private var displayTimer: Timer?

    func process(pixelBuffer: CVPixelBuffer, face: VNFaceObservation?) {
        guard !isProcessing else { return }
        isProcessing = true

        let handRequest = VNDetectHumanHandPoseRequest()
        handRequest.maximumHandCount = 2

        do {
            try sequenceHandler.perform([handRequest], on: pixelBuffer, orientation: .up)
            let handResults = handRequest.results as? [VNHumanHandPoseObservation] ?? []
            lastHandResults = handResults
            handle(handResults: handResults, face: face)
        } catch {
            print("PhoneDetector request error: \(error)")
        }
        isProcessing = false
    }

    func reset() {
        candidateSince = nil
        candidateFalseSince = nil
        notPhoneSince = nil
        isPhoneDetected = false
        detectionMode = nil
        currentDuration = 0
        totalPhoneTime = 0
        phoneStartTime = nil
        stopDurationTimer()
    }

    private func handle(handResults: [VNHumanHandPoseObservation]?, face: VNFaceObservation?) {
        let hands = handResults ?? []
        let faceBox = face?.boundingBox

        let candidates: [(hand: VNHumanHandPoseObservation, centroid: CGPoint)] = hands.compactMap { hand in
            guard let c = handCentroid(hand) else { return nil }
            return (hand, c)
        }

        // --- Gate ---
        var gateMode: PhoneDetectionMode?
        var handDist: CGFloat?
        var inZone = false

        if candidates.count >= 2 {
            let c0 = candidates[0].centroid
            let c1 = candidates[1].centroid
            let dx = c0.x - c1.x
            let dy = c0.y - c1.y
            let distance = (dx * dx + dy * dy).squareRoot()
            handDist = distance

            let bothInZone = isInPhoneZone(c0, faceBox: faceBox) && isInPhoneZone(c1, faceBox: faceBox)
            inZone = bothInZone
            if distance < handCloseThreshold && bothInZone {
                gateMode = .twoHanded
            }
        } else if candidates.count == 1 {
            let c = candidates[0].centroid
            let zoneOK = isInPhoneZone(c, faceBox: faceBox)
            let overlapsFace = overlapsFaceBox(c, faceBox: faceBox)
            inZone = zoneOK && !overlapsFace
            if zoneOK && !overlapsFace {
                gateMode = .oneHanded
            }
        }

        // --- Confirmation signals ---
        let pitch = pitchDown(face: face)
        debugPitch = pitch
        let pitchSignal = (pitch ?? 0) > pitchDownThreshold

        let gripSignal = candidates.contains { hasGripShape($0.hand) }
        debugGrip = gripSignal
        debugHandDist = handDist
        debugInZone = inZone

        let instantPhone = gateMode != nil && (pitchSignal || gripSignal)

        updateStateMachine(instantPhone: instantPhone, mode: gateMode)
    }

    private func updateStateMachine(instantPhone: Bool, mode: PhoneDetectionMode?) {
        let now = Date()

        if instantPhone {
            candidateFalseSince = nil
            if candidateSince == nil {
                candidateSince = now
            }
        } else {
            if candidateFalseSince == nil {
                candidateFalseSince = now
            }
            // Only drop the candidate clock after sustained absence (flicker grace).
            if let falseSince = candidateFalseSince, now.timeIntervalSince(falseSince) >= flickerGrace {
                candidateSince = nil
            }
        }

        if !isPhoneDetected {
            // Consider entering: need candidate held for enterSustain.
            if let since = candidateSince, now.timeIntervalSince(since) >= enterSustain {
                isPhoneDetected = true
                detectionMode = mode
                phoneStartTime = now
                currentDuration = 0
                notPhoneSince = nil
                startDurationTimer()
            }
        } else {
            // Consider exiting: need condition false for exitGrace.
            if instantPhone {
                notPhoneSince = nil
                if let mode { detectionMode = mode }
            } else {
                if notPhoneSince == nil {
                    notPhoneSince = now
                }
                if let since = notPhoneSince, now.timeIntervalSince(since) >= exitGrace {
                    if let startTime = phoneStartTime {
                        totalPhoneTime += now.timeIntervalSince(startTime)
                    }
                    isPhoneDetected = false
                    detectionMode = nil
                    phoneStartTime = nil
                    currentDuration = 0
                    candidateSince = nil
                    notPhoneSince = nil
                    stopDurationTimer()
                }
            }
        }
    }

    /// Hand centroid must sit below the face (looking-down zone) but not at
    /// desk level, and roughly centered under the face horizontally.
    private func isInPhoneZone(_ centroid: CGPoint, faceBox: CGRect?) -> Bool {
        guard let faceBox else { return false }
        guard centroid.y < faceBox.minY, centroid.y > zoneMinY else { return false }
        let faceCenterX = faceBox.midX
        return abs(centroid.x - faceCenterX) <= zoneHorizontalBand
    }

    /// Excludes chin-resting: hand overlapping/touching the face bounding box.
    private func overlapsFaceBox(_ centroid: CGPoint, faceBox: CGRect?) -> Bool {
        guard let faceBox else { return false }
        return faceBox.insetBy(dx: -0.05, dy: -0.05).contains(centroid)
    }

    /// face.pitch (macOS 12+, positive = nodding down). Falls back to a
    /// landmark proxy (eye-midline-to-nose vertical gap normalized by eye
    /// width, which compresses when looking down) if pitch is unavailable.
    private func pitchDown(face: VNFaceObservation?) -> CGFloat? {
        guard let face else { return nil }
        if let pitch = face.pitch {
            return CGFloat(truncating: pitch)
        }
        guard let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye?.normalizedPoints,
              let rightEye = landmarks.rightEye?.normalizedPoints,
              let nose = landmarks.nose?.normalizedPoints, !nose.isEmpty else {
            return nil
        }
        let eyeMidY = ((leftEye.map(\.y).reduce(0, +) / CGFloat(leftEye.count))
                       + (rightEye.map(\.y).reduce(0, +) / CGFloat(rightEye.count))) / 2
        let noseTipY = nose.map(\.y).min() ?? eyeMidY
        let leftEyeWidth = (leftEye.max(by: { $0.x < $1.x })?.x ?? 0) - (leftEye.min(by: { $0.x < $1.x })?.x ?? 0)
        guard leftEyeWidth > 0 else { return nil }
        // Smaller gap (relative to resting) reads as pitched down; this proxy
        // isn't in radians, so it's compared against the same threshold scale
        // empirically via the debug UI rather than treated as exact radians.
        return (eyeMidY - noseTipY) / leftEyeWidth
    }

    /// Grip shape: thumb confidently tracked, but several fingertips are
    /// occluded (low confidence) because they're curled behind a held phone.
    private func hasGripShape(_ hand: VNHumanHandPoseObservation) -> Bool {
        guard let points = try? hand.recognizedPoints(.all) else { return false }
        guard let thumbTip = points[.thumbTip], thumbTip.confidence > handConfidence else { return false }

        let fingertips: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip, .ringTip, .littleTip]
        let occludedCount = fingertips.filter { (points[$0]?.confidence ?? 0) < fingertipOccludedConfidence }.count
        return occludedCount >= occludedFingertipsRequired
    }

    /// Average location of all confident joints for a hand.
    private func handCentroid(_ hand: VNHumanHandPoseObservation) -> CGPoint? {
        guard let points = try? hand.recognizedPoints(.all) else { return nil }
        let confident = points.values.filter { $0.confidence > handConfidence }
        guard !confident.isEmpty else { return nil }
        let sumX = confident.reduce(0) { $0 + $1.location.x }
        let sumY = confident.reduce(0) { $0 + $1.location.y }
        return CGPoint(x: sumX / CGFloat(confident.count), y: sumY / CGFloat(confident.count))
    }

    private func startDurationTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let startTime = self.phoneStartTime else { return }
            Task { @MainActor in
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopDurationTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
}
