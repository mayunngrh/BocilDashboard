import SwiftUI
import AppKit

// MARK: - Theme

enum Bocil {
    private static func nsColor(_ s: String) -> NSColor {
        var v: UInt64 = 0
        Scanner(string: s.trimmingCharacters(in: .alphanumerics.inverted)).scanHexInt64(&v)
        return NSColor(
            red:   CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8)  & 0xFF) / 255,
            blue:  CGFloat(v         & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func adaptive(light: String, dark: String) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? nsColor(dark) : nsColor(light)
        }))
    }

    static let bg         = adaptive(light: "EAF9FF", dark: "0D141E")
    static let surface    = adaptive(light: "FFFFFF", dark: "151E2B")
    static let cardBorder = adaptive(light: "9FD8F5", dark: "2B3D4F")
    static let hairline   = adaptive(light: "D8ECFA", dark: "1E2D3D")
    static let accent     = adaptive(light: "102942", dark: "F2F7FC")
    static let accentSoft = adaptive(light: "78D8F8", dark: "78D8F8")
    static let onAccent   = Color(red: 16/255, green: 41/255, blue: 66/255) // always #102942 on accentSoft bg
    static let ink        = adaptive(light: "102942", dark: "F2F7FC")
    static let subtext    = adaptive(light: "5B7A94", dark: "A5B7C9")
    static let faint      = adaptive(light: "8BA4BB", dark: "65768A")
    static let danger     = adaptive(light: "A13D2C", dark: "C55343")

    static func header(_ size: CGFloat) -> Font { .custom("Silkscreen", size: size) }
    static func mono(_ size: CGFloat) -> Font   { .custom("SpaceMono-Regular", size: size) }
}

// MARK: - Nav tabs

enum BocilTab: String, CaseIterable, Identifiable {
    case home = "HOME", calendar = "CALENDAR", focus = "BOCAM", history = "HISTORY", settings = "SETTINGS"
    var id: String { rawValue }
}

// MARK: - Top Nav Bar

struct TopNavBar: View {
    @Binding var selected: BocilTab

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Bocil.accentSoft)
                    .frame(width: 30, height: 30)
                Text("BOCIL")
                    .font(Bocil.header(14))
                    .foregroundColor(Bocil.accentSoft)
                    .fixedSize()
            }
            .padding(.leading, 20)

            Spacer(minLength: 24)

            HStack(spacing: 2) {
                ForEach(BocilTab.allCases) { tab in
                    Button(action: { selected = tab }) {
                        Text(tab.rawValue)
                            .font(Bocil.header(14))
                            .tracking(0.5)
                            .fixedSize()
                            .foregroundColor(selected == tab ? Bocil.onAccent : Bocil.subtext)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(selected == tab ? Bocil.accentSoft : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 24)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Rectangle().fill(Bocil.accentSoft).frame(width: 7, height: 7)
                    Text("paired").font(Bocil.mono(12)).foregroundColor(Bocil.subtext).fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(Rectangle().stroke(Bocil.hairline, lineWidth: 1.5))
            }
            .padding(.trailing, 20)
        }
        .frame(height: 64)
        .background(Bocil.surface)
        .overlay(Rectangle().fill(Bocil.hairline).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Pixel Toggle

struct PixelToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(isOn ? Bocil.accentSoft : Bocil.hairline)
                    .frame(width: 38, height: 22)
                Rectangle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 3)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

