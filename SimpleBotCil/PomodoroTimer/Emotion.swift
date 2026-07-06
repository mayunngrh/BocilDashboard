//
//  Emotion.swift
//  SimpleBotCil
//

import Foundation

/// Mirrors the mood constants in FluxGarage_RoboEyes (DEFAULT, TIRED, ANGRY, HAPPY).
enum Emotion: String, CaseIterable {
    case happy = "HAPPY"
    case sad = "SAD"
    case mad = "MAD"
    case neutral = "NEUTRAL"

    /// The RoboEyes serial command this emotion maps to.
    var roboEyesCommand: String {
        switch self {
        case .happy: return "HAPPY"
        case .sad: return "TIRED"
        case .mad: return "ANGRY"
        case .neutral: return "DEFAULT"
        }
    }

    var emoji: String {
        switch self {
        case .happy: return "🙂"
        case .sad: return "😢"
        case .mad: return "😠"
        case .neutral: return "😐"
        }
    }
}
