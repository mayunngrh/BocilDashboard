//
//  EmotionDetector.swift
//  BocilDashboard
//

import Vision
import CoreImage
import Combine

struct EmotionMetrics {
    var mouthCurvature: CGFloat = 0   // corner height relative to lip-center, normalized by mouth width. + = smile, - = frown
    var mouthOpenness: CGFloat = 0    // inner lip gap normalized by mouth width
    var browToEyeGap: CGFloat = 0     // eyebrow distance above eyes, normalized by eye width
}

@MainActor
final class EmotionDetector: ObservableObject {
    @Published var currentEmotion: Emotion?
    @Published var faceDetected = false
    @Published var metrics = EmotionMetrics()
    @Published var faceLandmarks: VNFaceLandmarks2D?
    @Published var faceBoundingBox: CGRect = .zero
    @Published var lastFaceObservation: VNFaceObservation?

    private let sequenceHandler = VNSequenceRequestHandler()
    private var isProcessing = false

    // Smoothing buffer so a single noisy frame doesn't flip the displayed emotion.
    private var recentEmotions: [Emotion] = []
    private let smoothingWindow = 6

    func process(pixelBuffer: CVPixelBuffer) {
        guard !isProcessing else { return }
        isProcessing = true

        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let self else { return }
            let results = request.results as? [VNFaceObservation]
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

    private func handle(results: [VNFaceObservation]?) {
        guard let face = results?.first, let landmarks = face.landmarks else {
            faceDetected = false
            currentEmotion = nil
            faceLandmarks = nil
            lastFaceObservation = nil
            recentEmotions.removeAll()
            return
        }
        faceDetected = true
        lastFaceObservation = face
        faceLandmarks = landmarks
        faceBoundingBox = face.boundingBox

        guard let (computedMetrics, instantEmotion) = classify(landmarks: landmarks) else {
            return
        }
        metrics = computedMetrics

        recentEmotions.append(instantEmotion)
        if recentEmotions.count > smoothingWindow {
            recentEmotions.removeFirst()
        }
        currentEmotion = mostFrequent(in: recentEmotions)
    }

    private func mostFrequent(in emotions: [Emotion]) -> Emotion {
        var counts: [Emotion: Int] = [:]
        for emotion in emotions {
            counts[emotion, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .neutral
    }

    /// Heuristic classifier using mouth curvature/openness and eyebrow-to-eye
    /// gap, all normalized by feature-local scale (mouth width / eye width)
    /// rather than the face bounding box, since the bbox is unstable under
    /// head tilt/pitch and camera distance.
    private func classify(landmarks: VNFaceLandmarks2D) -> (EmotionMetrics, Emotion)? {
        guard let outerLips = landmarks.outerLips?.normalizedPoints, outerLips.count >= 4,
              let innerLips = landmarks.innerLips?.normalizedPoints, innerLips.count >= 4,
              let leftEyebrow = landmarks.leftEyebrow?.normalizedPoints,
              let rightEyebrow = landmarks.rightEyebrow?.normalizedPoints,
              let leftEye = landmarks.leftEye?.normalizedPoints,
              let rightEye = landmarks.rightEye?.normalizedPoints else {
            return nil
        }

        // Mouth corners by x-extreme, top/bottom lip by y-extreme. Vision's
        // point ordering within a region isn't guaranteed, so always derive
        // landmarks geometrically rather than assuming fixed indices.
        let leftCorner = outerLips.min(by: { $0.x < $1.x })!
        let rightCorner = outerLips.max(by: { $0.x < $1.x })!
        let mouthWidth = rightCorner.x - leftCorner.x
        guard mouthWidth > 0 else { return nil }

        let topLip = outerLips.max(by: { $0.y < $1.y })!
        let bottomLip = outerLips.min(by: { $0.y < $1.y })!
        let cornerY = (leftCorner.y + rightCorner.y) / 2
        let lipMidY = (topLip.y + bottomLip.y) / 2
        let mouthCurvature = (cornerY - lipMidY) / mouthWidth

        let innerTop = innerLips.max(by: { $0.y < $1.y })!
        let innerBottom = innerLips.min(by: { $0.y < $1.y })!
        let mouthOpenness = (innerTop.y - innerBottom.y) / mouthWidth

        let leftEyeWidth = (leftEye.max(by: { $0.x < $1.x })!.x - leftEye.min(by: { $0.x < $1.x })!.x)
        let rightEyeWidth = (rightEye.max(by: { $0.x < $1.x })!.x - rightEye.min(by: { $0.x < $1.x })!.x)
        let eyeWidth = (leftEyeWidth + rightEyeWidth) / 2

        let browY = (leftEyebrow.map(\.y).reduce(0, +) / CGFloat(leftEyebrow.count)
                     + rightEyebrow.map(\.y).reduce(0, +) / CGFloat(rightEyebrow.count)) / 2
        let eyeY = (leftEye.map(\.y).reduce(0, +) / CGFloat(leftEye.count)
                    + rightEye.map(\.y).reduce(0, +) / CGFloat(rightEye.count)) / 2
        let browToEyeGap = eyeWidth > 0 ? (browY - eyeY) / eyeWidth : 0

        let computedMetrics = EmotionMetrics(
            mouthCurvature: mouthCurvature,
            mouthOpenness: mouthOpenness,
            browToEyeGap: browToEyeGap
        )

        // Thresholds calibrated against mouth-width-normalized curvature
        // (typically ranges roughly -0.25...0.25) rather than face-height-
        // normalized values, which made smiles and frowns indistinguishable
        // from noise.
        // Calibrated from user data:
        // neutral:  curvature ~-0.122 to 0.20  (resting/slight smile)
        // happy:    curvature ~0.22+            (clear smile — corners pulled up)
        // mad:      curvature ~-0.357, browGap ~0.493
        // browToEyeGap is too noisy to use for happy detection for this user
        let smileThreshold: CGFloat   = -0.12   // slight smile → happy
        let frownThreshold: CGFloat   = -0.18   // real frown → sad or mad
        let madBrowThreshold: CGFloat =  0.35   // high brow tension while frowning → mad

        let emotion: Emotion
        if mouthCurvature > smileThreshold {
            emotion = .happy
        } else if mouthCurvature < frownThreshold && browToEyeGap > madBrowThreshold {
            emotion = .mad
        } else if mouthCurvature < frownThreshold {
            emotion = .sad
        } else {
            emotion = .neutral
        }

        return (computedMetrics, emotion)
    }
}
