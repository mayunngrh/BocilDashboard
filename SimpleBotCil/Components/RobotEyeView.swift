import SwiftUI

/// Two glowing blue "OLED eyes" drawn on the robot's screen, matching the look
/// of a real two-eye display (rounded squares, no visible socket). Both eyes
/// drift together toward the cursor, like a gaze shifting on the screen.
/// Positioning is computed from the real image aspect ratio so it lands
/// correctly at any frame size (scaledToFit letterboxes the image, so the
/// displayed image rect isn't the same as the view's frame).
struct RobotEyeView: View {
    @State private var gazeOffset: CGSize = .zero
    @State private var isBlinking = false

    // Native Robot.png pixel size, used to reproduce scaledToFit's letterboxing.
    private let imageSize = CGSize(width: 896, height: 1185)

    // Screen center and each eye's half-spacing, as a fraction of the *image*
    // (not the view) — measured from the robot's screen artwork.
    private let screenCenterFraction = CGPoint(x: 0.345, y: 0.44)
    private let eyeSpacingFraction: CGFloat = 0.075

    // Eye size as a fraction of the fitted image width, so it scales with frame size.
    private let eyeWidthFraction: CGFloat = 0.1
    private let eyeAspect: CGFloat = 1.25   // height / width

    private let eyeColor = Color(red: 0.45, green: 0.85, blue: 1.0)

    var body: some View {
        GeometryReader { geometry in
            let imageRect = fittedImageRect(in: geometry.size)
            let screenCenter = CGPoint(
                x: imageRect.minX + screenCenterFraction.x * imageRect.width,
                y: imageRect.minY + screenCenterFraction.y * imageRect.height
            )
            let eyeSpacing = eyeSpacingFraction * imageRect.width
            let eyeWidth = eyeWidthFraction * imageRect.width
            let eyeHeight = eyeWidth * eyeAspect
            let maxDrift = eyeWidth * 0.4

            ZStack {
                Image("Robot")
                    .resizable()
                    .scaledToFit()

                eyePair(width: eyeWidth, height: eyeHeight, spacing: eyeSpacing)
                    .position(screenCenter)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    updateGaze(cursorLocation: location, eyeCenter: screenCenter, maxDrift: maxDrift)
                case .ended:
                    withAnimation(.easeOut(duration: 0.2)) { gazeOffset = .zero }
                }
            }
        }
        .task { await runBlinkLoop() }
    }

    /// Blinks at a random interval (3–6s) forever, for as long as this view
    /// is on screen. Most blinks are a single flutter; occasionally it's a
    /// quick double-blink, for a more organic, less metronomic feel.
    private func runBlinkLoop() async {
        while !Task.isCancelled {
            let delay = Double.random(in: 2.0...5.0)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await blinkOnce()
            guard !Task.isCancelled else { return }

            // ~30% of the time, follow up with a second quick blink.
            if Double.random(in: 0...1) < 0.3 {
                try? await Task.sleep(nanoseconds: 130_000_000)
                guard !Task.isCancelled else { return }
                await blinkOnce()
            }
        }
    }

    private func blinkOnce() async {
        withAnimation(.easeIn(duration: 0.06)) { isBlinking = true }
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.1)) { isBlinking = false }
    }

    private func eyePair(width: CGFloat, height: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: max(0, spacing * 2 - width)) {
            glowingEye(width: width, height: height)
            glowingEye(width: width, height: height)
        }
        .offset(gazeOffset)
        .animation(.easeOut(duration: 0.12), value: gazeOffset)
    }

    private func glowingEye(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width * 0.35, style: .continuous)
            .fill(eyeColor)
            .frame(width: width, height: height)
            .scaleEffect(x: 1, y: isBlinking ? 0.08 : 1, anchor: .center)
            .shadow(color: eyeColor.opacity(0.9), radius: width * 0.5)
            .shadow(color: eyeColor.opacity(0.6), radius: width * 1.1)
    }

    /// The rect the image actually occupies inside `containerSize` after
    /// `scaledToFit` (i.e. the letterboxed/pillarboxed placement).
    private func fittedImageRect(in containerSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        var fittedSize = containerSize
        if imageAspect > containerAspect {
            fittedSize.height = containerSize.width / imageAspect
        } else {
            fittedSize.width = containerSize.height * imageAspect
        }

        let origin = CGPoint(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2
        )
        return CGRect(origin: origin, size: fittedSize)
    }

    private func updateGaze(cursorLocation: CGPoint, eyeCenter: CGPoint, maxDrift: CGFloat) {
        let dx = cursorLocation.x - eyeCenter.x
        let dy = cursorLocation.y - eyeCenter.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > 0 else { return }

        let angle = atan2(dy, dx)
        let magnitude = min(maxDrift, distance / 8)

        withAnimation {
            gazeOffset = CGSize(width: magnitude * cos(angle), height: magnitude * sin(angle))
        }
    }
}

#Preview {
    RobotEyeView()
        .frame(width: 260, height: 260)
        .background(Color.gray.opacity(0.2))
}
