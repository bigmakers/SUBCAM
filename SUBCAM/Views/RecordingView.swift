import SwiftUI
import AVFoundation
import Photos

struct RecordingView: View {
    @StateObject private var cameraService = CameraService()
    @StateObject private var recordingService = VideoRecordingService()
    @StateObject private var speechService = SpeechRecognitionService()
    @StateObject private var aiVisionService = AIVisionService()
    @ObservedObject private var settings = SettingsService.shared

    @State private var showSavedAlert = false
    @State private var savedSuccess = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(
                session: cameraService.captureSession,
                videoRotationAngle: cameraService.videoRotationAngle
            )
            .saturation(settings.monochromeMode ? 0 : 1)
            .contrast(settings.monochromeMode && !settings.cinematicMode ? 1.1 : settings.cinematicMode ? 1.15 : 1)
            .ignoresSafeArea()

            // Subtitle overlay (preview)
            SubtitleOverlayView(
                text: settings.subtitleMode == .speech ? speechService.displayText : aiVisionService.displayText,
                cinemaScope: settings.cinemaScope,
                subtitleScale: settings.subtitleSize.scale,
                isRecording: recordingService.isRecording,
                letterboxColor: settings.letterboxColor,
                subtitlePosition: settings.subtitlePosition,
                subtitleFont: settings.subtitleFont
            )
            .ignoresSafeArea()

            // Controls overlay
            if cameraService.isLandscape {
                landscapeControls
            } else {
                portraitControls
            }

            // Mode badge (top center)
            modeBadge
        }
        .onAppear {
            setupServices()
        }
        .onDisappear {
            Task {
                await teardownServices()
            }
        }
        .onChange(of: settings.speechLanguageId) { _, newLang in
            speechService.setLanguage(newLang)
        }
        .onChange(of: settings.cinemaScope) { _, newValue in
            guard !recordingService.isRecording else { return }
            cameraService.setCinemaScope(newValue)
            recordingService.cinemaScope = newValue
        }
        .onChange(of: settings.cinematicMode) { _, newValue in
            guard !recordingService.isRecording else { return }
            cameraService.setCinematicMode(newValue)
            recordingService.cinematicMode = newValue
        }
        .onChange(of: settings.monochromeMode) { _, newValue in
            guard !recordingService.isRecording else { return }
            recordingService.monochromeMode = newValue
        }
        .onChange(of: settings.letterboxColor) { _, newValue in
            recordingService.letterboxColor = newValue
        }
        .onChange(of: settings.subtitlePosition) { _, newValue in
            recordingService.subtitlePosition = newValue
        }
        .onChange(of: settings.subtitleMode) { _, newValue in
            guard !recordingService.isRecording else { return }
            recordingService.subtitleMode = newValue
            if newValue == .speech {
                aiVisionService.stop()
            } else {
                speechService.stopRecognition()
            }
        }
        .onChange(of: settings.aiProvider) { _, _ in
            aiVisionService.updateProvider()
        }
        .onChange(of: settings.cameraLens) { _, newValue in
            guard !recordingService.isRecording else { return }
            cameraService.switchLens(newValue)
        }
        .alert(savedSuccess ? L10n.saveComplete : L10n.saveFailed, isPresented: $showSavedAlert) {
            Button("OK") {}
        } message: {
            Text(savedSuccess ? L10n.videoSavedMessage : L10n.videoSaveFailedMessage)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                onVideoQualityChanged: { quality in
                    cameraService.applyVideoQuality(quality)
                },
                onHDRChanged: { enabled in
                    cameraService.applyHDR(enabled)
                },
                onExposureChanged: { ev in
                    cameraService.applyExposureBias(ev)
                },
                onCinemaScopeChanged: { enabled in
                    cameraService.setCinemaScope(enabled)
                    recordingService.cinemaScope = enabled
                },
                onCinematicModeChanged: { enabled in
                    cameraService.setCinematicMode(enabled)
                    recordingService.cinematicMode = enabled
                },
                onLensChanged: { lens in
                    cameraService.switchLens(lens)
                }
            )
        }
    }

    // MARK: - Mode badge (always visible, top center)

    private var modeBadge: some View {
        VStack {
            HStack(spacing: 6) {
                if settings.cinemaScope {
                    badgeLabel("Scope")
                }
                if settings.cinematicMode {
                    badgeLabel("Cinematic")
                }
                if settings.monochromeMode {
                    badgeLabel("Mono")
                }
                if !settings.cinemaScope && !settings.cinematicMode && !settings.monochromeMode {
                    badgeLabel("Standard")
                }
            }
            .padding(.top, cameraService.isLandscape ? 8 : 56)
            Spacer()
        }
    }

    private func badgeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.35))
            .cornerRadius(4)
    }

    // MARK: - Portrait controls

    private var portraitControls: some View {
        VStack {
            HStack {
                Spacer()
                settingsButton
                    .padding(.trailing, 20)
                    .padding(.top, 60)
            }

            if recordingService.isRecording {
                recordingTimerBadge
            }

            Spacer()

            recordButton
                .padding(.bottom, 40)
        }
    }

    // MARK: - Landscape controls

    private var landscapeControls: some View {
        HStack {
            VStack {
                settingsButton
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.top, 16)

            Spacer()

            // Center top: timer
            VStack {
                if recordingService.isRecording {
                    recordingTimerBadge
                }
                Spacer()
            }
            .padding(.top, 8)

            Spacer()

            // Right rail: record button
            VStack {
                Spacer()
                recordButton
                Spacer()
            }
            .padding(.trailing, 30)
        }
    }

    // MARK: - Shared components

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .disabled(recordingService.isRecording)
        .opacity(recordingService.isRecording ? 0.45 : 1.0)
    }

    private var recordingTimerBadge: some View {
        HStack {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
            Text(formatDuration(recordingService.recordingDuration))
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.5))
        .cornerRadius(20)
    }

    private var recordButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)

                if recordingService.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.red)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 60, height: 60)
                }
            }
        }
    }

    // MARK: - Actions

    private func setupServices() {
        // Force free-tier defaults if not pro
        if !settings.isProUnlocked {
            settings.videoQuality = .hd1080p30
            settings.hdrEnabled = false
            settings.exposureBias = .minus1
        }

        cameraService.setupSession()

        let coordinator = SampleBufferCoordinator(
            recordingService: recordingService,
            speechService: speechService,
            aiVisionService: aiVisionService
        )
        cameraService.coordinator = coordinator

        recordingService.speechService = speechService
        recordingService.aiVisionService = aiVisionService
        recordingService.subtitleMode = settings.subtitleMode

        // Apply saved settings
        speechService.setLanguage(settings.speechLanguageId)
        aiVisionService.updateProvider()
        cameraService.setCinemaScope(settings.cinemaScope)
        cameraService.setCinematicMode(settings.cinematicMode)
        recordingService.cinemaScope = settings.cinemaScope
        recordingService.cinematicMode = settings.cinematicMode
        recordingService.monochromeMode = settings.monochromeMode
        recordingService.letterboxColor = settings.letterboxColor
        recordingService.subtitlePosition = settings.subtitlePosition

        cameraService.startSession()
    }

    private func teardownServices() async {
        // Stop recording first (while subtitles are still active)
        if recordingService.isRecording,
           let url = await recordingService.stopRecording() {
            _ = await VideoRecordingService.saveToPhotoLibrary(url: url)
            try? FileManager.default.removeItem(at: url)
        }

        // Then clear subtitle services
        speechService.stopRecognition()
        aiVisionService.stop()
        cameraService.stopSession()
    }

    private func toggleRecording() {
        if recordingService.isRecording {
            Task {
                // Unlock capture connection rotation
                cameraService.isRecordingActive = false

                // Stop recording first (while subtitles still active), then clear subtitles
                if let url = await recordingService.stopRecording() {
                    let success = await VideoRecordingService.saveToPhotoLibrary(url: url)
                    await MainActor.run {
                        savedSuccess = success
                        showSavedAlert = true
                    }
                    try? FileManager.default.removeItem(at: url)
                }
                // Clear subtitles after recording is finalized
                if settings.subtitleMode == .speech {
                    speechService.stopRecognition()
                } else {
                    aiVisionService.stop()
                }
            }
        } else {
            // Lock capture connection rotation to prevent buffer dimension changes
            cameraService.isRecordingActive = true

            recordingService.letterboxColor = settings.letterboxColor
            recordingService.subtitleMode = settings.subtitleMode
            recordingService.startRecording()
            if settings.subtitleMode == .speech {
                speechService.startRecognition()
            } else {
                aiVisionService.start()
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// Coordinator that bridges AVCaptureOutput delegates to our services
class SampleBufferCoordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let recordingService: VideoRecordingService
    let speechService: SpeechRecognitionService
    let aiVisionService: AIVisionService

    init(recordingService: VideoRecordingService, speechService: SpeechRecognitionService, aiVisionService: AIVisionService) {
        self.recordingService = recordingService
        self.speechService = speechService
        self.aiVisionService = aiVisionService
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            recordingService.appendVideoBuffer(sampleBuffer)
            aiVisionService.processVideoBuffer(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            recordingService.appendAudioBuffer(sampleBuffer)
            speechService.appendAudioBuffer(sampleBuffer)
        }
    }
}
