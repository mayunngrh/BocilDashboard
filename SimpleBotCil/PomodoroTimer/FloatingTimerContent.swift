//
//  FloatingTimerContent.swift
//  SimpleBotCil
//

import SwiftUI

struct FloatingTimerContent: View {
    @ObservedObject var timerManager: TimerManager

    var body: some View {
        VStack(spacing: 16) {
            Text(timerManager.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(timerManager.remainingFormatted)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(height: 60)

            HStack(spacing: 10) {
                Button("Stop") {
                    timerManager.stop()
                    FloatingTimerWindow.shared.close()
                    MenuBarTimer.shared.stop()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 280, height: 220)
    }
}

#Preview {
    FloatingTimerContent(timerManager: TimerManager())
}
