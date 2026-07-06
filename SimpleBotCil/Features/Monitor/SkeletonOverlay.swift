//
//  SkeletonOverlay.swift
//  SimpleBotCil
//

import SwiftUI
import Vision

struct SkeletonOverlay: View {
    let handResults: [VNHumanHandPoseObservation]
    let faceObservation: VNFaceObservation?
    let frameSize: CGSize
    let bufferSize: CGSize

    var body: some View {
        Canvas { context, size in
            // Draw hand skeletons
            for hand in handResults {
                drawHandSkeleton(hand, context: &context, size: size)
            }

            // Draw face landmarks
            if let face = faceObservation, let landmarks = face.landmarks {
                drawFaceLandmarks(landmarks, context: &context, size: size)
            }
        }
    }

    private func drawHandSkeleton(_ hand: VNHumanHandPoseObservation, context: inout GraphicsContext, size: CGSize) {
        guard let points = try? hand.recognizedPoints(.all) else { return }

        let joints = Array(points.values)
        let highConfidence = joints.filter { $0.confidence > 0.3 }

        // Draw joints as circles
        for point in highConfidence {
            let pos = mapPoint(point.location, size: size)
            let circle = Path(ellipseIn: CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8))
            context.fill(circle, with: .color(.cyan))
        }

        // Draw connections (simplified hand skeleton)
        let connections: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
            (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
            (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
            (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
            (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
        ]

        for (from, to) in connections {
            guard let p1 = points[from], let p2 = points[to],
                  p1.confidence > 0.3, p2.confidence > 0.3 else { continue }
            let start = mapPoint(p1.location, size: size)
            let end = mapPoint(p2.location, size: size)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(.cyan), lineWidth: 2)
        }
    }

    /// Maps Vision normalized coords to the SwiftUI canvas.
    /// Vision orientation=.up returns points with origin at bottom-left, 0...1 range.
    /// SwiftUI canvas origin is top-left.
    /// The preview layer uses .resizeAspectFill: the buffer is scaled to fill the canvas
    /// while maintaining aspect ratio, so parts are cropped. We map from buffer normalized
    /// coords directly to canvas pixel coords, accounting for Y-flip only.
    private func mapPoint(_ p: CGPoint, size: CGSize) -> CGPoint {
        let displayX = p.x
        let displayY = 1.0 - p.y

        return CGPoint(x: displayX * size.width, y: displayY * size.height)
    }

    private func drawFaceLandmarks(_ landmarks: VNFaceLandmarks2D, context: inout GraphicsContext, size: CGSize) {
        let regions: [(VNFaceLandmarkRegion2D?)] = [
            landmarks.leftEye,
            landmarks.rightEye,
            landmarks.nose,
            landmarks.leftEyebrow,
            landmarks.rightEyebrow,
            landmarks.outerLips,
        ]

        for region in regions {
            guard let region else { continue }
            for point in region.normalizedPoints {
                let pos = mapPoint(point, size: size)
                let circle = Path(ellipseIn: CGRect(x: pos.x - 3, y: pos.y - 3, width: 6, height: 6))
                context.fill(circle, with: .color(.green))
            }
        }
    }
}
