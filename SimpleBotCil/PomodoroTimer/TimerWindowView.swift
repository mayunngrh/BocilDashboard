//
//  TimerWindowView.swift
//  SimpleBotCil
//

import SwiftUI

struct TimerWindowView: View {
    @ObservedObject var timerMgr: TimerManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Text(timerMgr.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(timerMgr.remainingFormatted)
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .frame(height: 70)
            }

            HStack(spacing: 12) {
                Button("Stop Timer") {
                    timerMgr.stop()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button("Dismiss") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 280, height: 220)
    }
}

#Preview {
    TimerWindowView(timerMgr: TimerManager(), isPresented: .constant(true))
}
