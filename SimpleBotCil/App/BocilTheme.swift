import SwiftUI

// MARK: - Theme

enum Bocil {
    private static func c(_ hex: String) -> Color {
        let s = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        return Color(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8)  & 0xFF) / 255,
            blue:  Double(v         & 0xFF) / 255
        )
    }

    static let bg         = c("EAF9FF")  // Background
    static let cardBorder = c("9FD8F5")  // Border
    static let hairline   = c("D8ECFA")  // Dividers/separators
    static let accent     = c("102942")  // Strong emphasis (maps to Primary Text)
    static let accentSoft = c("78D8F8")  // Primary interactive
    static let ink        = c("102942")  // Primary Text
    static let subtext    = c("5B7A94")  // Secondary Text
    static let faint      = c("8BA4BB")  // Tertiary Text
    static let danger     = c("A13D2C")  // Danger

    static func header(_ size: CGFloat) -> Font { .custom("Silkscreen", size: size) }
    static func mono(_ size: CGFloat) -> Font   { .custom("SpaceMono-Regular", size: size) }
}

// MARK: - Nav tabs

enum BocilTab: String, CaseIterable, Identifiable {
    case home = "HOME", calendar = "CALENDAR", focus = "FOCUS", history = "HISTORY", settings = "SETTINGS"
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
                    .foregroundColor(Bocil.cardBorder)
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
                            .foregroundColor(selected == tab ? Bocil.ink : Bocil.subtext)
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
                    HStack(spacing: 2) {
                        ZStack(alignment: .leading) {
                            Rectangle().stroke(Bocil.cardBorder, lineWidth: 1.2).frame(width: 16, height: 9)
                            Rectangle().fill(Bocil.cardBorder).frame(width: 7, height: 5).padding(.leading, 1.5)
                        }
                        Rectangle().fill(Bocil.cardBorder).frame(width: 2, height: 4)
                    }
                    Text("50%").font(Bocil.mono(12)).foregroundColor(Bocil.subtext).fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(Rectangle().stroke(Bocil.hairline, lineWidth: 1.5))

                HStack(spacing: 6) {
                    Circle().fill(Bocil.accentSoft).frame(width: 7, height: 7)
                    Text("paired").font(Bocil.mono(12)).foregroundColor(Bocil.subtext).fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(Rectangle().stroke(Bocil.hairline, lineWidth: 1.5))
            }
            .padding(.trailing, 20)
        }
        .frame(height: 64)
        .background(Color.white)
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
