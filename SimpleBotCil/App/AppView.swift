import SwiftUI

struct AppView: View {
    @ObservedObject var serial: SerialManager
    @State private var selectedTab: BocilTab = .focus

    var body: some View {
        VStack(spacing: 0) {
            TopNavBar(selected: $selectedTab)
            tabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: 1000, minHeight: 700)
        .background(
            ZStack {
                Bocil.bg
                Image("dot-pattern")
                    .resizable()
                    .scaledToFill()
                    .blendMode(.multiply)
                    .opacity(0.08)
            }
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:     ComingSoonView(label: "HOME")
        case .calendar: CalendarView()
        case .focus:    FocusView(serial: serial)
        case .history:  HistoryView()
        case .settings: SettingsView()
        }
    }
}

struct ComingSoonView: View {
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            Text(label)
                .font(Bocil.header(32))
                .foregroundColor(Bocil.faint)
            Text("coming soon")
                .font(Bocil.mono(14))
                .foregroundColor(Bocil.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AppView(serial: SerialManager())
}
