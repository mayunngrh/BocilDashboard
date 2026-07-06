//
//  TimerManager.swift
//  SimpleBotCil
//

import Foundation
import UserNotifications
import Combine

@MainActor
final class TimerManager: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var remainingSeconds: Int = 0
    @Published var label: String = ""

    private var countdownTask: Task<Void, Never>?

    // MARK: - Parse

    /// Returns duration in seconds from a natural-language command, or nil if not a timer request.
    func parseDuration(from command: String) -> Int? {
        let text = command.lowercased()

        // Must look like a timer intent
        let timerKeywords = ["focus", "timer", "remind", "minute", "hour", "second", "work", "break", "pomodoro"]
        guard timerKeywords.contains(where: { text.contains($0) }) else { return nil }

        var totalSeconds = 0

        // "X hours"
        if let hours = extractNumber(before: ["hour", "hours", "hr", "hrs"], in: text) {
            totalSeconds += hours * 3600
        }
        // "X minutes"
        if let mins = extractNumber(before: ["minute", "minutes", "min", "mins"], in: text) {
            totalSeconds += mins * 60
        }
        // "X seconds"
        if let secs = extractNumber(before: ["second", "seconds", "sec", "secs"], in: text) {
            totalSeconds += secs
        }

        // Named shortcuts
        if totalSeconds == 0 {
            if text.contains("pomodoro") { totalSeconds = 25 * 60 }
            else if text.contains("half an hour") || text.contains("half hour") { totalSeconds = 30 * 60 }
            else if text.contains("quarter hour") || text.contains("quarter of an hour") { totalSeconds = 15 * 60 }
        }

        return totalSeconds > 0 ? totalSeconds : nil
    }

    private func extractNumber(before keywords: [String], in text: String) -> Int? {
        let words = text.components(separatedBy: .whitespaces)
        for (index, word) in words.enumerated() {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            if keywords.contains(where: { clean.hasPrefix($0) }) && index > 0 {
                let prev = words[index - 1].trimmingCharacters(in: .punctuationCharacters)
                if let n = Int(prev) { return n }
                if let n = wordToNumber(prev) { return n }
            }
        }
        return nil
    }

    private func wordToNumber(_ word: String) -> Int? {
        let map: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "fifteen": 15, "twenty": 20, "twenty-five": 25, "thirty": 30,
            "forty-five": 45, "sixty": 60, "ninety": 90
        ]
        return map[word]
    }

    // MARK: - Timer

    func start(seconds: Int, label timerLabel: String) {
        stop()
        remainingSeconds = seconds
        label = timerLabel
        isRunning = true

        scheduleNotification(after: seconds, label: timerLabel)

        countdownTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remaining -= 1
                await MainActor.run { [weak self] in
                    self?.remainingSeconds = remaining
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let finishedLabel = self.label.isEmpty ? "Timer" : self.label
                self.isRunning = false
                self.label = ""
                FloatingTimerWindow.shared.close()
                MenuBarTimer.shared.stop()
                print("Timer done — showing alert for: \(finishedLabel)")
                AlertSound.shared.play()
                TimerDoneAlert.shared.show(label: finishedLabel)
            }
        }
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        isRunning = false
        remainingSeconds = 0
        label = ""
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["botcil-timer"])
    }

    // MARK: - Notification

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted {
                print("Notification permission denied — timer will still count down but won't alert")
            }
        }
    }

    private func scheduleNotification(after seconds: Int, label: String) {
        let content = UNMutableNotificationContent()
        content.title = "BotCil Timer Done!"
        content.body = "\(label) complete. Time's up!"
        content.sound = nil

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: "botcil-timer", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Notification error: \(error)") }
        }
    }

    // MARK: - Formatting

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
