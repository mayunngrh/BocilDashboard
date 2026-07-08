import SwiftUI

/// Which bottom corner the pixel-art tail points out of.
enum SpeechBubbleTailSide {
    case leading
    case trailing
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
        let bubbleBottom = rect.maxY - tailHeight

        switch tailSide {
        case .trailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            // right edge continues all the way down to the tail tip
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            // diagonal back up to the tail base
            path.addLine(to: CGPoint(x: rect.maxX - tailWidth, y: bubbleBottom))
            // rest of the bottom edge
            path.addLine(to: CGPoint(x: rect.minX, y: bubbleBottom))
            path.closeSubpath()

        case .leading:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: bubbleBottom))
            // rest of the bottom edge
            path.addLine(to: CGPoint(x: rect.minX + tailWidth, y: bubbleBottom))
            // diagonal down to the tail tip
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }

        return path
    }
}
