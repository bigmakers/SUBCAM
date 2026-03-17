import AVFoundation
import UIKit

class CameraService: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let videoQueue = DispatchQueue(label: "com.subcam.videoQueue")
    private let audioQueue = DispatchQueue(label: "com.subcam.audioQueue")

    // Strong reference to coordinator to prevent deallocation
    var coordinator: SampleBufferCoordinator? {
        didSet {
            videoDataOutput.setSampleBufferDelegate(coordinator, queue: videoQueue)
            audioDataOutput.setSampleBufferDelegate(coordinator, queue: audioQueue)
        }
    }

    @Published var isSessionRunning = false
    @Published var isCinemaScope = false
    @Published var isCinematicMode = false

    // Single source of truth for orientation — drives preview, recording, and UI layout
    @Published var isLandscape = false
    @Published var videoRotationAngle: CGFloat = 90

    /// When true, the capture connection's rotation angle is frozen
    /// (prevents buffer dimension changes that break AVAssetWriter mid-recording).
    /// Preview and UI orientation still update freely.
    var isRecordingActive = false

    private var cameraDevice: AVCaptureDevice?
    private var currentCameraInput: AVCaptureDeviceInput?

    func setupSession() {
        let settings = SettingsService.shared

        captureSession.beginConfiguration()
        captureSession.sessionPreset = settings.videoQuality.sessionPreset

        // Camera input — use selected lens, fallback to wide angle
        let lens = settings.cameraLens
        let camera = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let camera,
              let cameraInput = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(cameraInput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(cameraInput)
        currentCameraInput = cameraInput
        cameraDevice = camera

        // Microphone input
        guard let mic = AVCaptureDevice.default(for: .audio),
              let micInput = try? AVCaptureDeviceInput(device: mic),
              captureSession.canAddInput(micInput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(micInput)

        // Video data output
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }

        // Audio data output
        if captureSession.canAddOutput(audioDataOutput) {
            captureSession.addOutput(audioDataOutput)
        }

        captureSession.commitConfiguration()

        // Apply initial orientation
        updateVideoOrientation()

        // Apply camera device settings
        applyFrameRate(settings.videoQuality.frameRate)
        applyHDR(settings.hdrEnabled)
        applyExposureBias(settings.exposureBias.evValue)

        // Listen for device orientation changes
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    @objc private func deviceOrientationDidChange() {
        updateVideoOrientation()
    }

    func setCinemaScope(_ enabled: Bool) {
        isCinemaScope = enabled
    }

    func setCinematicMode(_ enabled: Bool) {
        isCinematicMode = enabled
        applyCinematicCameraSettings()
    }

    // MARK: - Lens

    func switchLens(_ lens: CameraLens) {
        guard let currentInput = currentCameraInput else { return }

        let newDevice = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let newDevice,
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

        captureSession.beginConfiguration()
        captureSession.removeInput(currentInput)
        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
            currentCameraInput = newInput
            cameraDevice = newDevice
        } else {
            // Fallback: re-add old input
            captureSession.addInput(currentInput)
        }
        captureSession.commitConfiguration()

        // Re-apply device settings
        let settings = SettingsService.shared
        applyFrameRate(settings.videoQuality.frameRate)
        applyHDR(settings.hdrEnabled)
        applyExposureBias(settings.exposureBias.evValue)
        applyCinematicCameraSettings()
        updateVideoOrientation()
    }

    // MARK: - Video Quality

    func applyVideoQuality(_ quality: VideoQuality) {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = quality.sessionPreset
        captureSession.commitConfiguration()
        applyFrameRate(quality.frameRate)
    }

    private func applyFrameRate(_ fps: Double) {
        guard let device = cameraDevice else { return }
        do {
            try device.lockForConfiguration()
            var bestFormat: AVCaptureDevice.Format?
            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let isCorrectResolution: Bool
                if captureSession.sessionPreset == .hd4K3840x2160 {
                    isCorrectResolution = dimensions.width >= 3840
                } else {
                    isCorrectResolution = dimensions.width >= 1920 && dimensions.width < 3840
                }
                guard isCorrectResolution else { continue }
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= fps {
                        bestFormat = format
                        break
                    }
                }
                if bestFormat != nil { break }
            }
            if let format = bestFormat {
                device.activeFormat = format
            }
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.unlockForConfiguration()
        } catch {
            print("Failed to set frame rate: \(error)")
        }
    }

    // MARK: - HDR

    func applyHDR(_ enabled: Bool) {
        guard let device = cameraDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = enabled
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to set HDR: \(error)")
        }
    }

    // MARK: - Exposure

    func applyExposureBias(_ ev: Float) {
        guard let device = cameraDevice else { return }
        do {
            try device.lockForConfiguration()
            let clampedEV = max(device.minExposureTargetBias, min(ev, device.maxExposureTargetBias))
            device.setExposureTargetBias(clampedEV, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            print("Failed to set exposure: \(error)")
        }
    }

    // MARK: - Orientation (single source of truth)

    private func updateVideoOrientation() {
        let lock = SettingsService.shared.orientationLock

        let angle: CGFloat
        let landscape: Bool

        // If locked, use fixed orientation
        switch lock {
        case .portrait:
            angle = 90
            landscape = false
        case .landscape:
            // Use device orientation to pick left vs right, default to landscapeLeft
            let deviceOrientation = UIDevice.current.orientation
            if deviceOrientation == .landscapeRight {
                angle = 180
            } else {
                angle = 0
            }
            landscape = true
        case .auto:
            // Detect from device / interface orientation
            let detected = Self.detectOrientation()
            angle = detected.angle
            landscape = detected.landscape
        }

        // Only update the capture connection when NOT recording.
        // Changing the connection angle mid-recording would change buffer
        // dimensions and break AVAssetWriter.
        if !isRecordingActive {
            if let connection = videoDataOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
        }

        // Always publish to preview layer and UI — they can rotate freely
        DispatchQueue.main.async {
            self.videoRotationAngle = angle
            self.isLandscape = landscape
        }
    }

    /// Detect orientation from device / interface orientation
    private static func detectOrientation() -> (angle: CGFloat, landscape: Bool) {
        let deviceOrientation = UIDevice.current.orientation

        if deviceOrientation == .unknown || deviceOrientation == .faceUp || deviceOrientation == .faceDown {
            let interfaceOrientation: UIInterfaceOrientation
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first {
                interfaceOrientation = windowScene.interfaceOrientation
            } else {
                interfaceOrientation = .portrait
            }

            switch interfaceOrientation {
            case .landscapeLeft:  return (0, true)
            case .landscapeRight: return (180, true)
            case .portraitUpsideDown: return (270, false)
            default: return (90, false)
            }
        } else {
            switch deviceOrientation {
            case .landscapeLeft:  return (0, true)
            case .landscapeRight: return (180, true)
            case .portraitUpsideDown: return (270, false)
            default: return (90, false)
            }
        }
    }

    // MARK: - Cinematic

    private func applyCinematicCameraSettings() {
        guard let device = cameraDevice else { return }

        do {
            try device.lockForConfiguration()

            if isCinematicMode {
                let targetZoom: CGFloat = 2.0
                let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
                device.videoZoomFactor = min(targetZoom, maxZoom)

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = true
                }
            } else {
                device.videoZoomFactor = 1.0

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = false
                }
            }

            device.unlockForConfiguration()
        } catch {
            print("Failed to configure camera: \(error)")
        }
    }

    // MARK: - Lifecycle

    func startSession() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = self?.captureSession.isRunning ?? false
            }
        }
    }

    func stopSession() {
        guard captureSession.isRunning else { return }
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = false
            }
        }
    }
}
