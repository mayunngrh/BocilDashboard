//
//  FocusModeViewModel.swift
//  BocilDashboard
//
//  Business logic for Focus Mode: detects sitting + phone use,
//  triggers robot commands when thresholds are exceeded.
//

import Foundation
import Combine

@MainActor
final class FocusModeViewModel: ObservableObject {
    @Published var isFocusModeOn = false

    private let robotController: RobotController
    private let posture: PostureDetector
    private let phone: PhoneDetector

    // Thresholds
    private let sittingLimit: TimeInterval = 15 * 60   // 15 minutes
    private let phoneLimit: TimeInterval = 10          // 10 seconds
    private let reAlertCooldown: TimeInterval = 30

    // Cooldown tracking
    private var lastSittingAlertAt: Date?
    private var lastPhoneAlertAt: Date?

    init(
        robotController: RobotController,
        posture: PostureDetector,
        phone: PhoneDetector
    ) {
        self.robotController = robotController
        self.posture = posture
        self.phone = phone
    }

    func checkThresholds() {
        checkSittingThreshold()
        checkPhoneThreshold()
    }

    private func checkSittingThreshold() {
        guard isFocusModeOn, posture.currentPosture == .sitting else { return }
        guard posture.currentDuration >= sittingLimit else { return }

        if shouldAlert(lastSittingAlertAt) {
            lastSittingAlertAt = Date()
            robotController.sendCommand("ANGRY")
        }
    }

    private func checkPhoneThreshold() {
        guard isFocusModeOn, phone.isPhoneDetected else { return }
        guard phone.currentDuration >= phoneLimit else { return }

        if shouldAlert(lastPhoneAlertAt) {
            lastPhoneAlertAt = Date()
            robotController.sendCommand("ANGRY")
        }
    }

    private func shouldAlert(_ last: Date?) -> Bool {
        guard let last else { return true }
        return Date().timeIntervalSince(last) >= reAlertCooldown
    }

    func reset() {
        lastSittingAlertAt = nil
        lastPhoneAlertAt = nil
    }
}
