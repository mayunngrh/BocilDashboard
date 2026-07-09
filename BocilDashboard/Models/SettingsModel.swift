import SwiftUI
import Combine

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

/// Persisted, app-wide language choice. Applied at the root via
/// `.environment(\.locale, ...)` (see `AppView`), so every `Text` and
/// formatter downstream re-renders in the new language immediately —
/// no restart needed.
final class AppLanguageManager: ObservableObject {
    @Published var mode: LanguageMode {
        didSet { UserDefaults.standard.set(mode.localeIdentifier, forKey: "bocil.language") }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "bocil.language") ?? ""
        mode = saved.isEmpty ? .english : LanguageMode(localeIdentifier: saved)
    }

    var locale: Locale { Locale(identifier: mode.localeIdentifier) }
}

/// Reads the persisted language choice directly from `UserDefaults`, for use
/// in plain model code (e.g. `Conversation`'s computed date labels) that has
/// no `@Environment` to read from. Views should prefer `@Environment(\.locale)`
/// (it's what actually drives re-rendering on a language change) — this is
/// only for formatting deep in non-View model types.
enum CurrentLocale {
    static var value: Locale {
        let saved = UserDefaults.standard.string(forKey: "bocil.language") ?? ""
        let mode = saved.isEmpty ? LanguageMode.english : LanguageMode(localeIdentifier: saved)
        return Locale(identifier: mode.localeIdentifier)
    }
}
