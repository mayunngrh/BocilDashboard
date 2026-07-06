//
//  TimerWindowManager.swift
//  SimpleBotCil
//

import Foundation
import Combine

@MainActor
final class TimerWindowManager: ObservableObject {
    @Published var isTimerWindowOpen = false
    @Published var remainingSeconds = 0
    @Published var label = ""

    func openTimer(seconds: Int, label: String) {
        remainingSeconds = seconds
        self.label = label
        isTimerWindowOpen = true
    }

    func closeTimer() {
        isTimerWindowOpen = false
        remainingSeconds = 0
        label = ""
    }

    func updateCountdown(seconds: Int) {
        remainingSeconds = seconds
        if seconds <= 0 {
            closeTimer()
        }
    }

    var remainingFormatted: String {
        let h = remainingSeconds / 3600
        let m = (remainingSeconds % 3600) / 60
        let s = remainingSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}
