import Foundation
import Combine

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
