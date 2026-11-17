@preconcurrency import AVFoundation
import Foundation
import Observation

public enum CameraAuthState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

@MainActor
@Observable
public final class CameraMirrorController {
    public private(set) var authState: CameraAuthState = .notDetermined
    public private(set) var isRunning = false
    public private(set) var statusMessage: String?

    public let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.notchnest.camera")
    private var isConfigured = false

    public init() {
        refreshAuthState()
    }

    public func refreshAuthState() {
        if AVCaptureDevice.default(for: .video) == nil {
            authState = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authState = .authorized
        case .notDetermined:
            authState = .notDetermined
        case .denied, .restricted:
            authState = .denied
        @unknown default:
            authState = .denied
        }
    }

    public func requestAndStart() async {
        refreshAuthState()
        if authState == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            refreshAuthState()
            if !granted { return }
        }
        guard authState == .authorized else { return }
        startIfAuthorized()
    }

    public func startIfAuthorized() {
        refreshAuthState()
        guard authState == .authorized else { return }
        guard !isRunning else { return }

        let captureSession = session
        let configured = isConfigured
        sessionQueue.async { [weak self] in
            if !configured {
                captureSession.beginConfiguration()
                captureSession.sessionPreset = .medium
                if let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                } else {
                    captureSession.commitConfiguration()
                    Task { @MainActor in
                        self?.statusMessage = "Unable to open camera device."
                    }
                    return
                }
                captureSession.commitConfiguration()
                Task { @MainActor in
                    self?.isConfigured = true
                }
            }

            if !captureSession.isRunning {
                captureSession.startRunning()
            }
            Task { @MainActor in
                self?.isRunning = true
                self?.statusMessage = nil
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        let captureSession = session
        sessionQueue.async { [weak self] in
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            Task { @MainActor in
                self?.isRunning = false
            }
        }
    }
}
