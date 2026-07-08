import SwiftUI

struct AppView: View {
    @ObservedObject var serial: SerialManager
    @EnvironmentObject var appearance:    AppearanceManager
    @EnvironmentObject var focusStore:    FocusStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var connectionSettings = RobotConnectionSettings()
    @State private var selectedTab: BocilTab = .home

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
                    .blendMode(colorScheme == .dark ? .screen : .multiply)
                    .opacity(colorScheme == .dark ? 0.05 : 0.08)
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(appearance.colorScheme)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            HomeView(
                onOpenCalendar: { selectedTab = .calendar },
                onOpenFocus:    { selectedTab = .focus    },
                onStartFocus:   {
                    focusStore.pendingAutoStart = true
                    selectedTab = .focus
                }
            )
        case .calendar: CalendarView()
        case .focus:    FocusView(serial: serial, connectionSettings: connectionSettings)
        case .history:  HistoryView()
        case .settings: SettingsView(connectionSettings: connectionSettings)
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
        .environmentObject(AppearanceManager())
        .environmentObject(CalendarStore())
        .environmentObject(FocusStore())
        .environmentObject(ProfileBackendService())
}
