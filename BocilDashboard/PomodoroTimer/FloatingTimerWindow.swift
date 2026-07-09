//
//  FloatingTimerWindow.swift
//  BocilDashboard
//

import Foundation
import AppKit
import SwiftUI

class FloatingTimerWindow: NSObject, NSWindowDelegate {
    static let shared = FloatingTimerWindow()

    private var windows: [NSWindow] = []

    func show(timerManager: TimerManager) {
        closeAll()

        for screen in NSScreen.screens {
            let content = FloatingTimerContent(timerManager: timerManager)
            let hosting = NSHostingController(rootView: content)

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
                styleMask: [.titled],  // no .closable, no .resizable — locked
                backing: .buffered,
                defer: false
            )
            win.title = "BotCil Timer"
            win.contentViewController = hosting
            win.level = .screenSaver  // above everything including full-screen apps
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.isMovable = false
            win.isMovableByWindowBackground = false
            win.isReleasedWhenClosed = false
            win.delegate = self

            // Pin to top-right of each screen
            pinToTopRight(win, screen: screen)

            win.orderFrontRegardless()
            windows.append(win)
        }

        // Re-pin if screen config changes (external monitor plugged/unplugged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func close() {
        NotificationCenter.default.removeObserver(self)
        closeAll()
    }

    private func closeAll() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func pinToTopRight(_ win: NSWindow, screen: NSScreen) {
        let f = screen.visibleFrame
        let x = f.maxX - win.frame.width - 16
        let y = f.maxY - win.frame.height - 16
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func screensChanged() {
        for (index, win) in windows.enumerated() {
            if index < NSScreen.screens.count {
                pinToTopRight(win, screen: NSScreen.screens[index])
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }
}
