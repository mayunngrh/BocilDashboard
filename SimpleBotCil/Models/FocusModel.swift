import Foundation

enum FocusSession {
    static let durations: [Int] = [30, 60, 90]
}

enum PersonalityMode: String, CaseIterable, Hashable {
    case calm = "CALM"
    case energetic = "ENERGETIC"
    case professional = "PROFESSIONAL"

    var subtitle: String {
        switch self {
        case .calm: return "Gentle, thoughtful nudges"
        case .energetic: return "Uplifting, motivational"
        case .professional: return "Direct, efficient"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Hashable {
    case system = "SYSTEM"
    case light = "LIGHT"
    case dark = "DARK"

    var subtitle: String {
        switch self {
        case .system: return "Follow your system settings"
        case .light: return "Always light mode"
        case .dark: return "Always dark mode"
        }
    }
}

enum LanguageMode: String, CaseIterable, Hashable {
    case english = "ENGLISH"
    case spanish = "SPANISH"
    case french = "FRENCH"

    var subtitle: String {
        switch self {
        case .english: return "English (US)"
        case .spanish: return "Español"
        case .french: return "Français"
        }
    }
}
