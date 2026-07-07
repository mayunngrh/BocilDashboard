import Foundation
import Combine

enum FocusSession {
    static let durations: [Int] = [30, 60, 90]
}

// MARK: - FocusStore

final class FocusStore: ObservableObject {
    @Published var sessionActive = false
    @Published var currentSeconds = 0       // elapsed in the live session
    @Published var todayFocusSeconds = 0   // accumulated from completed sessions today
    @Published var pendingAutoStart = false // Home sets this; FocusView consumes it

    // Total focus minutes for today (live session included)
    var totalTodayMinutes: Int {
        (todayFocusSeconds + (sessionActive ? currentSeconds : 0)) / 60
    }

    func start() {
        currentSeconds = 0
        sessionActive = true
    }

    func stop() {
        if sessionActive { todayFocusSeconds += currentSeconds }
        sessionActive = false
        currentSeconds = 0
    }

    // Called every second by FocusView's timer
    func tick(effectiveMinutes: Int?) {
        guard sessionActive else { return }
        currentSeconds += 1
        if let mins = effectiveMinutes, currentSeconds >= mins * 60 { stop() }
    }
}

// MARK: - Settings enums (used by SettingsView)

enum PersonalityMode: String, CaseIterable, Hashable {
    case calm = "CALM"
    case energetic = "ENERGETIC"
    case professional = "PROFESSIONAL"

    var subtitle: String {
        switch self {
        case .calm:         return "Gentle, thoughtful nudges"
        case .energetic:    return "Uplifting, motivational"
        case .professional: return "Direct, efficient"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Hashable {
    case system = "SYSTEM"
    case light  = "LIGHT"
    case dark   = "DARK"

    var subtitle: String {
        switch self {
        case .system: return "Follow your system settings"
        case .light:  return "Always light mode"
        case .dark:   return "Always dark mode"
        }
    }
}

enum LanguageMode: String, CaseIterable, Hashable {
    case english = "ENGLISH"
    case spanish = "SPANISH"
    case french  = "FRENCH"

    var subtitle: String {
        switch self {
        case .english: return "English (US)"
        case .spanish: return "Español"
        case .french:  return "Français"
        }
    }
}
