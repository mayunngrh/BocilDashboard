//
//  ThinkingDetector.swift
//  BocilDashboard
//
//  Detects a "thinking" pose — hand(s) resting at or near the face: chin rest,
//  temple touch, praying hands in front of the face, or hands clasped behind
//  the head. This is deliberately the complement of PhoneDetector: phone use is
//  hands *below* the face (looking down) and explicitly NOT overlapping it,
//  whereas thinking is hands *at or above* face level, touching or framing it.
//  The two zones don't overlap, so a chin-rest never reads as phone use and a
//  looking-down phone grip never reads as thinking.
//

import Vision
import CoreImage
import Combine

@MainActor
final class ThinkingDetector: ObservableObject {
    @Published var isThinking = false
    @Published var currentDuration: TimeInterval = 0
    @Published var totalThinkingTime: TimeInterval = 0
    @Published var lastHandResults: [VNHumanHandPoseObservation] = []

    // Debug metrics for live threshold calibration (mirrors PhoneDetector).
    @Published var debugHandsAtFace: Int = 0
    @Published var debugOverlapsFace: Bool = false
    @Published var debugAboveHead: Bool = false

    private let sequenceHandler = VNSequenceRequestHandler()
    private var isProcessing = false

    private let handConfidence: VNConfidence = 0.3

    // A hand touching the face counts even when its centroid sits just outside
    // the reported box — Vision's face box is tight, so expand it a little.
    private let faceOverlapInset: CGFloat = 0.05

    // Hands-behind-head zone: centroid above the face box, within a horizontal
    // band around the face center. The band is wider than phone's because
    // elbows-out poses splay the hands away from center.
    private let aboveHeadBand: CGFloat = 0.45
    private let aboveHeadMaxGap: CGFloat = 0.30   // how far above the face box still counts

    // Time-based state machine (same shape as PhoneDetector): a sustained pose
    // is required to enter, and a grace period before exiting, so a hand merely
    // passing across the face doesn't flag as thinking.
    private var candidateSince: Date?
    private var candidateFalseSince: Date?
    private var notThinkingSince: Date?
    private let enterSustain: TimeInterval = 1.5
    private let flickerGrace: TimeInterval = 1.0
    private let exitGrace: TimeInterval = 2.0

    private var thinkingStartTime: Date?
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
            print("ThinkingDetector request error: \(error)")
        }
        isProcessing = false
    }

    func reset() {
        candidateSince = nil
        candidateFalseSince = nil
        notThinkingSince = nil
        isThinking = false
        currentDuration = 0
        totalThinkingTime = 0
        thinkingStartTime = nil
        stopDurationTimer()
    }

    private func handle(handResults: [VNHumanHandPoseObservation]?, face: VNFaceObservation?) {
        let hands = handResults ?? []
        let faceBox = face?.boundingBox

        let centroids: [CGPoint] = hands.compactMap { handCentroid($0) }

        var overlapsFace = false
        var aboveHead = false
        var handsAtFace = 0

        for centroid in centroids {
            if isOverlappingFace(centroid, faceBox: faceBox) {
                overlapsFace = true
                handsAtFace += 1
            } else if isAboveHead(centroid, faceBox: faceBox) {
                aboveHead = true
                handsAtFace += 1
            }
        }

        debugHandsAtFace = handsAtFace
        debugOverlapsFace = overlapsFace
        debugAboveHead = aboveHead

        // Only meaningful when a face is present — no face means we can't place
        // the hands relative to it, so we treat it as "not thinking".
        let instantThinking = faceBox != nil && (overlapsFace || aboveHead)

        updateStateMachine(instantThinking: instantThinking)
    }

    private func updateStateMachine(instantThinking: Bool) {
        let now = Date()

        if instantThinking {
            candidateFalseSince = nil
            if candidateSince == nil {
                candidateSince = now
            }
        } else {
            if candidateFalseSince == nil {
                candidateFalseSince = now
            }
            if let falseSince = candidateFalseSince, now.timeIntervalSince(falseSince) >= flickerGrace {
                candidateSince = nil
            }
        }

        if !isThinking {
            if let since = candidateSince, now.timeIntervalSince(since) >= enterSustain {
                isThinking = true
                thinkingStartTime = now
                currentDuration = 0
                notThinkingSince = nil
                startDurationTimer()
            }
        } else {
            if instantThinking {
                notThinkingSince = nil
            } else {
                if notThinkingSince == nil {
                    notThinkingSince = now
                }
                if let since = notThinkingSince, now.timeIntervalSince(since) >= exitGrace {
                    if let startTime = thinkingStartTime {
                        totalThinkingTime += now.timeIntervalSince(startTime)
                    }
                    isThinking = false
                    thinkingStartTime = nil
                    currentDuration = 0
                    candidateSince = nil
                    notThinkingSince = nil
                    stopDurationTimer()
                }
            }
        }
    }

    /// Hand centroid touching the face: chin rest, temple touch, or praying
    /// hands directly over the face. Uses an expanded box so a hand at the edge
    /// still counts.
    private func isOverlappingFace(_ centroid: CGPoint, faceBox: CGRect?) -> Bool {
        guard let faceBox else { return false }
        return faceBox.insetBy(dx: -faceOverlapInset, dy: -faceOverlapInset).contains(centroid)
    }

    /// Hand centroid above the face box (hands clasped behind the head), within
    /// a horizontal band around the face center.
    private func isAboveHead(_ centroid: CGPoint, faceBox: CGRect?) -> Bool {
        guard let faceBox else { return false }
        guard centroid.y >= faceBox.maxY, centroid.y <= faceBox.maxY + aboveHeadMaxGap else { return false }
        return abs(centroid.x - faceBox.midX) <= aboveHeadBand
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
            guard let self, let startTime = self.thinkingStartTime else { return }
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
