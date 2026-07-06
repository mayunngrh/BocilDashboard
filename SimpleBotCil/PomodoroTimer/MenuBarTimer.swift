//
//  MenuBarTimer.swift
//  SimpleBotCil
//

import AppKit
import Combine

class MenuBarTimer: NSObject {
    static let shared = MenuBarTimer()

    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?

    func start(timerManager: TimerManager) {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        }

        cancellable = timerManager.$remainingSeconds
            .combineLatest(timerManager.$isRunning, timerManager.$label)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remaining, isRunning, label in
                guard let self, let button = self.statusItem?.button else { return }
                if isRunning {
                    button.title = "⏱ \(timerManager.remainingFormatted)"
                    button.toolTip = label
                } else {
                    self.stop()
                }
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}
