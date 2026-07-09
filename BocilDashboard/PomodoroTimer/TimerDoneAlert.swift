//
//  TimerDoneAlert.swift
//  BocilDashboard
//

import AppKit
import SwiftUI

class TimerDoneAlert {
    static let shared = TimerDoneAlert()

    private var windows: [NSWindow] = []

    func show(label: String) {
        print("TimerDoneAlert.show called for: \(label)")
        dismiss()

        for screen in NSScreen.screens {
            let content = TimerDoneAlertContent(label: label) {
                TimerDoneAlert.shared.dismiss()
            }
            let hosting = NSHostingController(rootView: content)

            let winWidth: CGFloat = 360
            let winHeight: CGFloat = 110
            hosting.view.setFrameSize(NSSize(width: winWidth, height: winHeight))

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: winWidth, height: winHeight),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.contentViewController = hosting
            win.level = .screenSaver
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.isOpaque = true
            win.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
            win.isMovable = false
            win.isReleasedWhenClosed = false
            win.hasShadow = true

            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - winWidth / 2
            let endY = screenFrame.maxY - winHeight - 8
            let startY = screenFrame.maxY + 10  // just above visible area

            win.setFrameOrigin(NSPoint(x: x, y: startY))
            win.orderFrontRegardless()
            windows.append(win)

            print("Window created, animating to y=\(endY) on screen \(screen.localizedName)")

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.45
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                win.animator().setFrameOrigin(NSPoint(x: x, y: endY))
            }
        }

        // Auto-dismiss after 6 seconds if not clicked
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            self.dismiss()
        }

    }

    func dismiss() {
        AlertSound.shared.stop()
        let toClose = windows
        windows.removeAll()

        for win in toClose {
            let x = win.frame.origin.x
            let targetY = (NSScreen.main?.frame.maxY ?? 1200) + 10
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                win.animator().setFrameOrigin(NSPoint(x: x, y: targetY))
            }, completionHandler: {
                win.close()
            })
        }
    }
}

// MARK: - Alert content view

struct TimerDoneAlertContent: View {
    let label: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("🎉")
                .font(.system(size: 40))

            VStack(alignment: .leading, spacing: 3) {
                Text("Time's up!")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text(label + " complete")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }
}
