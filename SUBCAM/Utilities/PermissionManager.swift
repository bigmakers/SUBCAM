import AVFoundation
import Speech
import Photos
import SwiftUI

@MainActor
class PermissionManager: ObservableObject {
    @Published var cameraAuthorized = false
    @Published var microphoneAuthorized = false
    @Published var speechAuthorized = false

    var allAuthorized: Bool {
        cameraAuthorized && microphoneAuthorized && speechAuthorized
    }

    func checkPermissions() {
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestAllPermissions() async {
        cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        microphoneAuthorized = await AVCaptureDevice.requestAccess(for: .audio)

        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.speechAuthorized = (status == .authorized)
                    continuation.resume()
                }
            }
        }
    }
}
