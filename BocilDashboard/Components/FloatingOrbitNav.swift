import SwiftUI

/// Floating nav labels that orbit the robot. Hovering over one reveals a
/// speech-bubble with a short description of that page — clicking does nothing.
struct FloatingOrbitNav: View {
    @Binding var selectedTab: BocilTab

    private let imageSize = CGSize(width: 896, height: 1185)

    private struct OrbitItem {
        let tab: BocilTab
        let fraction: CGPoint
        let ampX: CGFloat
        let ampY: CGFloat
        let durationX: Double
        let durationY: Double
        let popupLines: [String]
        let tailSide: SpeechBubbleTailSide
        /// How far the bubble center is offset from the chip center.
        /// Tune this per-chip to control the gap between chip and popup.
        let popupOffset: CGSize
    }

    private let items: [OrbitItem] = [
        OrbitItem(tab: .home,     fraction: CGPoint(x: 0.04,  y: 0.10), ampX: 7,  ampY: 12, durationX: 3.6, durationY: 3.1,
                  popupLines: ["Hi! I'm Bocil.", "I'm ready to accompany you today."],
                  tailSide: .rightSide, popupOffset: CGSize(width: -280, height: 0)),

        OrbitItem(tab: .calendar, fraction: CGPoint(x: 0.80,  y: 0.02), ampX: 8,  ampY: 11, durationX: 3.1, durationY: 3.8,
                  popupLines: ["Tell me your plans.", "I'll organize your schedule."],
                  tailSide: .leftSide,  popupOffset: CGSize(width: 280,  height: 0)),

        OrbitItem(tab: .focus,    fraction: CGPoint(x: 1.06,  y: 0.42), ampX: 9,  ampY: 13, durationX: 4.0, durationY: 3.3,
                  popupLines: ["Ready to lock in?", "I'll keep you focused."],
                  tailSide: .leftSide,  popupOffset: CGSize(width: 280,  height: 0)),

        OrbitItem(tab: .history,  fraction: CGPoint(x: -0.08, y: 0.52), ampX: 9,  ampY: 11, durationX: 3.4, durationY: 4.2,
                  popupLines: ["Let's look back.", "Every conversation is here."],
                  tailSide: .rightSide, popupOffset: CGSize(width: -280, height: 0)),

        OrbitItem(tab: .settings, fraction: CGPoint(x: 0.52,  y: 1.04), ampX: 10, ampY: 8,  durationX: 3.9, durationY: 2.9,
                  popupLines: ["Customize me.", "Make me truly yours."],
                  tailSide: .leftSide,  popupOffset: CGSize(width: 280,  height: 0)),
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
                    popupLines: item.popupLines,
                    tailSide: item.tailSide,
                    popupOffset: item.popupOffset
                )
                .position(
                    x: rect.minX + item.fraction.x * rect.width,
                    y: rect.minY + item.fraction.y * rect.height
                )
            }
        }
    }

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

/// One floating nav badge. Drifts continuously with independent x/y cycles.
/// On hover, a speech bubble fades in adjacent to the chip.
private struct FloatingBadge: View {
    let tab: BocilTab
    let isSelected: Bool
    let ampX: CGFloat
    let ampY: CGFloat
    let durationX: Double
    let durationY: Double
    let popupLines: [String]
    let tailSide: SpeechBubbleTailSide
    let popupOffset: CGSize

    @State private var driftX = false
    @State private var driftY = false
    @State private var wobble = false
    @State private var isHovered = false

    private var bubbleScaleAnchor: UnitPoint {
        switch tailSide {
        case .rightSide:  return .trailing
        case .leftSide:   return .leading
        case .trailing:   return .bottom
        case .leading:    return .bottom
        }
    }

    var body: some View {
        chipLabel
            .overlay(alignment: .center) {
                InfoBubble(lines: popupLines, tailSide: tailSide)
                    .offset(popupOffset)
                    .opacity(isHovered ? 1 : 0)
                    .scaleEffect(isHovered ? 1 : 0.94, anchor: bubbleScaleAnchor)
                    .animation(.easeOut(duration: 0.18), value: isHovered)
                    .allowsHitTesting(false)
                    .fixedSize()
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
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

    private var chipLabel: some View {
        Text(tab.displayNameKey)
            .font(Bocil.header(20))
            .tracking(0.5)
            .fixedSize()
            .foregroundColor(Bocil.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(isHovered ? Bocil.hairline : Bocil.surface)
            .clipShape(RoundedRectangle(cornerRadius: 0))
            .overlay(RoundedRectangle(cornerRadius: 0).stroke(isHovered ? Bocil.accentSoft : Bocil.cardBorder, lineWidth: 1.6))
            .shadow(color: .black.opacity(isHovered ? 0.28 : 0.2), radius: isHovered ? 14 : 10, x: 0, y: isHovered ? 7 : 5)
    }
}

private struct InfoBubble: View {
    let lines: [String]
    let tailSide: SpeechBubbleTailSide

    private let tailH: CGFloat = 16
    private let tailW: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(Bocil.mono(20))
                    .foregroundColor(Bocil.ink)
                    .fixedSize()
            }
        }
        .padding(.top, 16)
        .padding(.bottom, isBottomTail ? (16 + tailH) : 16)
        .padding(.leading, tailSide == .leftSide ? (20 + tailH) : 20)
        .padding(.trailing, tailSide == .rightSide ? (20 + tailH) : 20)
        .fixedSize()
        .background(
            SpeechBubbleShape(tailHeight: tailH, tailWidth: tailW, tailSide: tailSide)
                .fill(Bocil.surface)
        )
        .overlay(
            SpeechBubbleShape(tailHeight: tailH, tailWidth: tailW, tailSide: tailSide)
                .stroke(Bocil.accentSoft, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
    }

    private var isBottomTail: Bool {
        tailSide == .trailing || tailSide == .leading
    }
}
