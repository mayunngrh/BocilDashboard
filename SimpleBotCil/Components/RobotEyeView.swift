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
    @State private var isHappy = false
    @State private var giggle: CGFloat = 0   // 0 = rest, 1 = bobbed up (drives the giggle bounce)

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
        .task { await runMoodLoop() }
    }

    /// Every so often, the eyes curve into a happy "⌒ ⌒" arch and do a few
    /// quick bobs — a little giggle — then relax back to normal. Deliberately
    /// infrequent so it feels like a spontaneous moment, not a constant mood.
    /// The whole giggle lasts roughly 1–2 seconds.
    private func runMoodLoop() async {
        while !Task.isCancelled {
            let wait = Double.random(in: 9.0...18.0)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }

            // Clap into the smile (squash-blink hides the instant shape swap).
            await clapInto(happy: true)
            guard !Task.isCancelled else { return }

            // Giggle: a handful of quick up/down bobs (~0.2s each).
            let bounces = Int.random(in: 4...7)
            for _ in 0..<bounces {
                withAnimation(.easeOut(duration: 0.09)) { giggle = 1 }
                try? await Task.sleep(nanoseconds: 90_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.11)) { giggle = 0 }
                try? await Task.sleep(nanoseconds: 110_000_000)
                guard !Task.isCancelled else { return }
            }

            // Clap back to normal eyes.
            await clapInto(happy: false)
        }
    }

    /// Snaps the eyes to `happy` behind a quick squash-blink, so the shape
    /// change reads as a crisp "clap" rather than a fade.
    private func clapInto(happy: Bool) async {
        withAnimation(.easeIn(duration: 0.06)) { isBlinking = true }
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard !Task.isCancelled else { return }
        isHappy = happy   // instant swap while squashed shut — no fade is visible
        withAnimation(.easeOut(duration: 0.1)) { isBlinking = false }
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
        // Gaze drift plus the giggle bob (a quick upward hop while laughing).
        .offset(x: gazeOffset.width, y: gazeOffset.height - giggle * height * 0.16)
        .animation(.easeOut(duration: 0.12), value: gazeOffset)
    }

    private func glowingEye(width: CGFloat, height: CGFloat) -> some View {
        // Instant swap between shapes (no cross-fade) — the change is hidden
        // behind the squash-blink in `clapInto`, so it "claps" open into the
        // new expression.
        Group {
            if isHappy {
                HappyEyeShape().fill(eyeColor)
            } else {
                RoundedRectangle(cornerRadius: width * 0.35, style: .continuous).fill(eyeColor)
            }
        }
        .frame(width: width, height: height)
        .scaleEffect(isHappy ? 1.2 : 1, anchor: .center)          // happy eyes are a bit bigger
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

/// A happy, upward-curving crescent eye ("⌒") — a band that bulges up in the
/// middle and tapers to points at the sides, so two of them read as a content
/// smile. Fills its frame, so it drops into the same slot as the normal eye.
private struct HappyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let h = rect.height
        let tipY = rect.minY + h * 0.72          // side tips sit lower → taller arch
        let outerPeakY = rect.minY - h * 0.32    // upper arc peaks well above the top → more curve
        let innerPeakY = rect.minY + h * 0.16    // lower arc peak → keeps a nice band thickness

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: tipY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: tipY),
            control: CGPoint(x: rect.midX, y: outerPeakY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: tipY),
            control: CGPoint(x: rect.midX, y: innerPeakY)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    RobotEyeView()
        .frame(width: 260, height: 260)
        .background(Color.gray.opacity(0.2))
}
