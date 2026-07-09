import Foundation
import Combine
import SwiftUI

enum FocusSession {
    static let durations: [Int] = [30, 60, 90]
}

// MARK: - FocusStore

final class FocusStore: ObservableObject {
    @Published var sessionActive = false
    @Published var currentSeconds = 0
    @Published var todayFocusSeconds = 0
    @Published var pendingAutoStart = false
    @Published var targetMinutes: Int? = nil  // nil = no time limit (count up)

    // Bumped once each time a session finishes; `lastCompletedSeconds` holds
    // that session's length. Views observe the tick to post it to the backend
    // exactly once (a plain value change could miss two equal-length sessions).
    @Published private(set) var completedSessionTick = 0
    private(set) var lastCompletedSeconds = 0

    var totalTodayMinutes: Int {
        (todayFocusSeconds + (sessionActive ? currentSeconds : 0)) / 60
    }

    /// Seeds today's persisted total (from the backend on launch) so the Home
    /// summary reflects focus logged in earlier runs. Ignored mid-session so a
    /// refetch can't stomp a running count.
    func seedTodayFocus(seconds: Int) {
        guard !sessionActive else { return }
        todayFocusSeconds = seconds
    }

    private var timer: Foundation.Timer?

    func start(limitMinutes: Int? = nil) {
        currentSeconds = 0
        targetMinutes = limitMinutes
        sessionActive = true
        timer?.invalidate()
        let t = Foundation.Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.sessionActive else { return }
            self.currentSeconds += 1
            if let mins = self.targetMinutes, self.currentSeconds >= mins * 60 {
                self.stop()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if sessionActive {
            todayFocusSeconds += currentSeconds
            lastCompletedSeconds = currentSeconds
            completedSessionTick += 1
        }
        sessionActive = false
        currentSeconds = 0
        targetMinutes = nil
    }
}

// MARK: - Settings enums (used by SettingsView)

enum PersonalityMode: String, CaseIterable, Hashable {
    case calm = "CALM"
    case energetic = "ENERGETIC"
    case professional = "PROFESSIONAL"

    /// `rawValue` stays fixed English (used for `apiValue`/UserDefaults);
    /// these drive what's actually shown on screen, per language.
    var titleKey: LocalizedStringKey {
        switch self {
        case .calm:         return "settings.personality.calm.title"
        case .energetic:    return "settings.personality.energetic.title"
        case .professional: return "settings.personality.professional.title"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .calm:         return "settings.personality.calm.subtitle"
        case .energetic:    return "settings.personality.energetic.subtitle"
        case .professional: return "settings.personality.professional.subtitle"
        }
    }

    /// The backend config uses lowercase values ("calm", "energetic", …).
    var apiValue: String { rawValue.lowercased() }

    init?(apiValue: String) {
        guard let mode = PersonalityMode.allCases.first(where: {
            $0.rawValue.lowercased() == apiValue.lowercased()
        }) else { return nil }
        self = mode
    }
}

enum AppearanceMode: String, CaseIterable, Hashable {
    case system = "SYSTEM"
    case light  = "LIGHT"
    case dark   = "DARK"

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "settings.appearance.system.title"
        case .light:  return "settings.appearance.light.title"
        case .dark:   return "settings.appearance.dark.title"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .system: return "settings.appearance.system.subtitle"
        case .light:  return "settings.appearance.light.subtitle"
        case .dark:   return "settings.appearance.dark.subtitle"
        }
    }
}

enum LanguageMode: String, CaseIterable, Hashable {
    case english    = "ENGLISH"
    case spanish    = "SPANISH"
    case french     = "FRENCH"
    case indonesian = "INDONESIAN"

    /// The row's bold header — this one *is* translated (e.g. "ENGLISH" reads
    /// as "INGLÉS" in the Spanish UI), unlike `subtitle` below.
    var titleKey: LocalizedStringKey {
        switch self {
        case .english:    return "settings.language.english.title"
        case .spanish:    return "settings.language.spanish.title"
        case .french:     return "settings.language.french.title"
        case .indonesian: return "settings.language.indonesian.title"
        }
    }

    /// Each language's own name in its own script — always shown the same
    /// way regardless of the active app language (platform convention, same
    /// as Apple's own language pickers: "Español" isn't translated to
    /// "Spanish" when the UI is in English).
    var subtitle: String {
        switch self {
        case .english:    return "English (US)"
        case .spanish:    return "Español"
        case .french:     return "Français"
        case .indonesian: return "Bahasa Indonesia"
        }
    }

    /// BCP-47 identifier used to build the `Locale` applied via
    /// `.environment(\.locale, ...)` at the app root.
    var localeIdentifier: String {
        switch self {
        case .english:    return "en"
        case .spanish:    return "es"
        case .french:     return "fr"
        case .indonesian: return "id"
        }
    }

    init(localeIdentifier: String) {
        self = LanguageMode.allCases.first { $0.localeIdentifier == localeIdentifier } ?? .english
    }
}
