//
//  CameraManager.swift
//  SimpleBotCil
//

import AVFoundation
import Combine

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var errorMessage: String?
    @Published var bufferSize = CGSize(width: 640, height: 480)

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "CameraManager.session")

    var onFrame: ((CVPixelBuffer) -> Void)?

    func start() {
        Task {
            let granted = await requestAccess()
            isAuthorized = granted
            guard granted else {
                errorMessage = "Camera access was denied. Enable it in System Settings > Privacy & Security > Camera."
                return
            }
            configureSessionIfNeeded()
            sessionQueue.async { [session] in
                if !session.isRunning {
                    session.startRunning()
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private var didConfigure = false

    private func configureSessionIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        sessionQueue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            session.sessionPreset = .medium

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                Task { @MainActor in
                    self.errorMessage = "No camera found."
                }
                return
            }
            session.addInput(input)

            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            if self.bufferSize.width != CGFloat(w) || self.bufferSize.height != CGFloat(h) {
                self.bufferSize = CGSize(width: CGFloat(w), height: CGFloat(h))
            }
            self.onFrame?(pixelBuffer)
        }
    }
}
