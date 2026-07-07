import SwiftUI

final class AppearanceManager: ObservableObject {
    @Published var mode: AppearanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "bocil.appearance") }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "bocil.appearance") ?? ""
        mode = AppearanceMode(rawValue: saved) ?? .system
    }

    var colorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
