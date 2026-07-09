import SwiftUI

/// Which edge the pixel-art tail extends from.
enum SpeechBubbleTailSide {
    case leading      // tail at bottom-left corner, points down-left
    case trailing     // tail at bottom-right corner, points down-right
    case rightSide    // tail pokes out from right edge, vertically centered
    case leftSide     // tail pokes out from left edge, vertically centered
}

/// A pixel-art speech-bubble shape with a small blocky tail at the bottom,
/// matching Bocil's pixel aesthetic (see the reference chat-bubble icon).
/// Shared by HomeView's "I'm Bocil…" bubble and each row in History's chat list.
struct SpeechBubbleShape: Shape {
    var tailHeight: CGFloat = 16
    var tailWidth: CGFloat = 16
    var tailSide: SpeechBubbleTailSide = .trailing

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch tailSide {
        case .trailing:
            let bubbleBottom = rect.maxY - tailHeight
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - tailWidth, y: bubbleBottom))
            path.addLine(to: CGPoint(x: rect.minX, y: bubbleBottom))
            path.closeSubpath()

        case .leading:
            let bubbleBottom = rect.maxY - tailHeight
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: bubbleBottom))
            path.addLine(to: CGPoint(x: rect.minX + tailWidth, y: bubbleBottom))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()

        case .rightSide:
            // Tail pokes from the right edge, centered vertically
            let bubbleRight = rect.maxX - tailHeight
            let midY = rect.midY
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: bubbleRight, y: rect.minY))
            path.addLine(to: CGPoint(x: bubbleRight, y: midY - tailWidth / 2))
            path.addLine(to: CGPoint(x: rect.maxX, y: midY))
            path.addLine(to: CGPoint(x: bubbleRight, y: midY + tailWidth / 2))
            path.addLine(to: CGPoint(x: bubbleRight, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()

        case .leftSide:
            // Tail pokes from the left edge, centered vertically
            let bubbleLeft = rect.minX + tailHeight
            let midY = rect.midY
            path.move(to: CGPoint(x: bubbleLeft, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: bubbleLeft, y: rect.maxY))
            path.addLine(to: CGPoint(x: bubbleLeft, y: midY + tailWidth / 2))
            path.addLine(to: CGPoint(x: rect.minX, y: midY))
            path.addLine(to: CGPoint(x: bubbleLeft, y: midY - tailWidth / 2))
            path.closeSubpath()
        }

        return path
    }
}
