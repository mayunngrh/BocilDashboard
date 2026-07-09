import SwiftUI

/// The nav tabs, rendered as individual badges that gently float around the
/// robot instead of sitting in a static bar. Mirrors `TopNavBar`'s tabs and
/// selection, so tapping a badge here switches tabs exactly like the top bar.
///
/// Each badge is positioned as a fraction of the *robot image* (not the
/// container), reproducing the same scaledToFit letterboxing math
/// `RobotEyeView` uses for its eyes — so badges stay anchored to the robot's
/// actual silhouette (corners, sides, base) rather than drifting into empty
/// margin space when the container is much larger than the image.
struct FloatingOrbitNav: View {
    @Binding var selectedTab: BocilTab

    // Native Robot.png pixel size — must match RobotEyeView's.
    private let imageSize = CGSize(width: 896, height: 1185)

    private struct OrbitItem {
        let tab: BocilTab
        let fraction: CGPoint   // position relative to the image rect; can go slightly outside [0,1]
        let ampX: CGFloat
        let ampY: CGFloat
        let durationX: Double
        let durationY: Double
    }

    private let items: [OrbitItem] = [
        OrbitItem(tab: .home,     fraction: CGPoint(x: 0.04, y: 0.10), ampX: 7, ampY: 12, durationX: 3.6, durationY: 3.1),
        OrbitItem(tab: .calendar, fraction: CGPoint(x: 0.80, y: 0.02), ampX: 8, ampY: 11, durationX: 3.1, durationY: 3.8),
        OrbitItem(tab: .focus,    fraction: CGPoint(x: 1.06, y: 0.42), ampX: 9, ampY: 13, durationX: 4.0, durationY: 3.3),
        OrbitItem(tab: .history,  fraction: CGPoint(x: -0.08, y: 0.52), ampX: 9, ampY: 11, durationX: 3.4, durationY: 4.2),
        OrbitItem(tab: .settings, fraction: CGPoint(x: 0.52, y: 1.04), ampX: 10, ampY: 8, durationX: 3.9, durationY: 2.9),
    ]

    var body: some View {
        GeometryReader { geometry in
            let rect = fittedImageRect(in: geometry.size)

            ForEach(items.indices, id: \.self) { idx in
                let item = items[idx]
                FloatingBadge(
                    tab: item.tab,
                    isSelected: selectedTab == item.tab,
                    ampX: item.ampX,
                    ampY: item.ampY,
                    durationX: item.durationX,
                    durationY: item.durationY,
                    action: { selectedTab = item.tab }
                )
                .position(
                    x: rect.minX + item.fraction.x * rect.width,
                    y: rect.minY + item.fraction.y * rect.height
                )
            }
        }
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
}

/// One floating nav badge. Drifts continuously on independent x/y cycles
/// (different durations per axis) so the motion looks organic rather than a
/// simple up-down bob, plus a faint wobble for a "flying" feel.
private struct FloatingBadge: View {
    let tab: BocilTab
    let isSelected: Bool
    let ampX: CGFloat
    let ampY: CGFloat
    let durationX: Double
    let durationY: Double
    let action: () -> Void

    @State private var driftX = false
    @State private var driftY = false
    @State private var wobble = false
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(tab.displayNameKey)
                .font(Bocil.header(20))
                .tracking(0.5)
                .fixedSize()
                .foregroundColor(isSelected ? Bocil.onAccent : Bocil.ink)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(isSelected ? Bocil.accentSoft : (isHovered ? Bocil.hairline : Bocil.surface))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isHovered ? Bocil.accentSoft : Bocil.cardBorder, lineWidth: 1.6))
                .shadow(color: .black.opacity(isHovered ? 0.28 : 0.2), radius: isHovered ? 14 : 10, x: 0, y: isHovered ? 7 : 5)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.08 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .offset(x: driftX ? ampX : -ampX, y: driftY ? ampY : -ampY)
        .rotationEffect(.degrees(wobble ? 2.5 : -2.5))
        .onAppear {
            withAnimation(.easeInOut(duration: durationX).repeatForever(autoreverses: true)) {
                driftX = true
            }
            withAnimation(.easeInOut(duration: durationY).repeatForever(autoreverses: true)) {
                driftY = true
            }
            withAnimation(.easeInOut(duration: (durationX + durationY) / 2).repeatForever(autoreverses: true)) {
                wobble = true
            }
        }
    }
}
