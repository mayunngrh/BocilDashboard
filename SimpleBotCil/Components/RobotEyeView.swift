import SwiftUI

/// A blue eye that follows the cursor position within its socket.
/// Used to display the robot's "following eye" on the robot image.
struct RobotEyeView: View {
    @State private var irisOffset: CGPoint = .zero
    @State private var isHovered = false

    private let irisRadius: CGFloat = 8
    private let socketRadius: CGFloat = 22

    var body: some View {
        ZStack {
            // Robot image
            Image("Robot")
                .resizable()
                .scaledToFit()

            // White eye socket + blue iris overlay
            ZStack {
                // White socket
                Circle()
                    .fill(Color.white)
                    .frame(width: socketRadius * 2, height: socketRadius * 2)

                // Blue iris
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: irisRadius * 2, height: irisRadius * 2)
                    .offset(x: irisOffset.x, y: irisOffset.y)
                    .animation(.easeOut(duration: 0.1), value: irisOffset)
            }
            .position(x: 76, y: 60)  // Eye position on the robot screen
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                isHovered = true
                updateIrisPosition(cursorLocation: location)
            case .ended:
                isHovered = false
                withAnimation {
                    irisOffset = .zero
                }
            }
        }
    }

    private func updateIrisPosition(cursorLocation: CGPoint) {
        // Robot eye is at approximately (76, 60) relative to view
        let eyeCenter = CGPoint(x: 76, y: 60)

        // Calculate angle from eye to cursor
        let dx = cursorLocation.x - eyeCenter.x
        let dy = cursorLocation.y - eyeCenter.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > 0 else { return }

        // Normalize and constrain to socket radius
        let maxOffset = socketRadius - irisRadius
        let angle = atan2(dy, dx)

        let offsetX = min(maxOffset, distance / 50) * cos(angle)  // Scale with distance
        let offsetY = min(maxOffset, distance / 50) * sin(angle)

        withAnimation {
            irisOffset = CGPoint(x: offsetX, y: offsetY)
        }
    }
}

#Preview {
    RobotEyeView()
        .frame(width: 300, height: 300)
}
