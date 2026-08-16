import SwiftUI
import AVFoundation
import Photos

struct RecordingView: View {
    @StateObject private var cameraService = CameraService()
    @StateObject private var recordingService = VideoRecordingService()
    @StateObject private var speechService = SpeechRecognitionService()
    @StateObject private var aiVisionService = AIVisionService()
    @StateObject private var translationService = TranslationService()
    @ObservedObject private var settings = SettingsService.shared

    @State private var showSavedAlert = false
    @State private var savedSuccess = false
    @State private var showSettings = false

    @State private var focusPoint: CGPoint?
    @State private var showFocusIndicator = false
    @State private var focusIndicatorGeneration = 0
    @State private var pinchBaseZoom: CGFloat = 1.0
    @State private var showZoomChip = false
    @State private var zoomChipGeneration = 0
    @State private var showSavedToast = false
    @State private var recDotOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(
                session: cameraService.captureSession,
                videoRotationAngle: cameraService.videoRotationAngle,
                onTapFocus: { devicePoint, layerPoint in
                    cameraService.focusAndExpose(at: devicePoint)
                    let generation = focusIndicatorGeneration + 1
                    withAnimation(.easeOut(duration: 0.2)) {
                        focusIndicatorGeneration = generation
                        focusPoint = layerPoint
                        showFocusIndicator = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        guard generation == focusIndicatorGeneration else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            showFocusIndicator = false
                        }
                    }
                },
                onPinchZoom: { state, scale in
                    switch state {
                    case .began:
                        pinchBaseZoom = cameraService.currentZoomFactor
                        zoomChipGeneration += 1
                        withAnimation(.easeOut(duration: 0.15)) {
                            showZoomChip = true
                        }
                    case .changed:
                        cameraService.setZoomFactor(pinchBaseZoom * scale)
                    case .ended, .cancelled:
                        let generation = zoomChipGeneration
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            guard generation == zoomChipGeneration else { return }
                            withAnimation(.easeOut(duration: 0.15)) {
                                showZoomChip = false
                            }
                        }
                    default:
                        break
                    }
                }
            )
            .saturation(settings.monochromeMode ? 0 : 1)
            .contrast(settings.monochromeMode && !settings.cinematicMode ? 1.1 : settings.cinematicMode ? 1.15 : 1)
            .ignoresSafeArea()

            // Focus indicator
            if showFocusIndicator, let point = focusPoint {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.yellow, lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                    .position(point)
                    .id(focusIndicatorGeneration)
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
            }

            // Invisible owner of the on-device translation session (iOS 18+)
            SpeechTranslationHost(
                service: translationService,
                translation: settings.speechTranslation,
                sourceLanguageId: settings.speechLanguageId
            )

            // Subtitle overlay (preview)
            SubtitleOverlayView(
                text: previewSubtitleText,
                cinemaScope: settings.cinemaScope,
                subtitleScale: settings.subtitleSize.scale,
                isRecording: recordingService.isRecording,
                letterboxColor: settings.letterboxColor,
                subtitlePosition: settings.subtitlePosition,
                subtitleFont: settings.subtitleFont
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()

            // Controls overlay
            if cameraService.isLandscape {
                landscapeControls
            } else {
                portraitControls
            }

            // Mode badge (top center)
            modeBadge

            // Saved toast (top center, below mode badge)
            if showSavedToast {
                VStack {
                    savedToast
                        .padding(.top, cameraService.isLandscape ? 46 : 92)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
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
            translationService.clear()
            recordingService.speechTranslationActive = translationActive
        }
        .onChange(of: settings.speechTranslation) { _, _ in
            translationService.clear()
            recordingService.speechTranslationActive = translationActive
        }
        .onChange(of: speechService.displayText) { _, newText in
            guard translationActive else { return }
            translationService.submit(newText)
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
                translationService.clear()
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
                subtitleModeToggle
                    .padding(.leading, 20)
                    .padding(.top, 60)
                Spacer()
                settingsButton
                    .padding(.trailing, 20)
                    .padding(.top, 60)
            }

            if recordingService.isRecording {
                recordingTimerBadge
            }

            Spacer()

            if showZoomChip {
                zoomChip
                    .padding(.bottom, 12)
            }

            lensChips
                .padding(.bottom, 16)

            recordButton
                .padding(.bottom, 40)
        }
    }

    // MARK: - Landscape controls

    private var landscapeControls: some View {
        HStack {
            VStack {
                settingsButton
                subtitleModeToggle
                    .padding(.top, 12)
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

            // Right rail: lens chips + record button
            HStack(spacing: 16) {
                lensChipsVertical

                VStack {
                    Spacer()
                    if showZoomChip {
                        zoomChip
                            .padding(.bottom, 8)
                    }
                    recordButton
                    Spacer()
                }
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
                .opacity(recDotOpacity)
                .onAppear {
                    recDotOpacity = 1.0
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        recDotOpacity = 0.3
                    }
                }
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

                RoundedRectangle(cornerRadius: recordingService.isRecording ? 6 : 30)
                    .fill(.red)
                    .frame(
                        width: recordingService.isRecording ? 30 : 60,
                        height: recordingService.isRecording ? 30 : 60
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recordingService.isRecording)
            }
        }
    }

    private var zoomChip: some View {
        Text(String(format: "%.1fx", cameraService.currentZoomFactor))
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())
    }

    private var lensChips: some View {
        HStack(spacing: 10) {
            lensChip(.ultraWide)
            lensChip(.wide)
        }
    }

    private var lensChipsVertical: some View {
        VStack(spacing: 10) {
            lensChip(.ultraWide)
            lensChip(.wide)
        }
    }

    private func lensChip(_ lens: CameraLens) -> some View {
        let isSelected = settings.cameraLens == lens
        return Button {
            settings.cameraLens = lens
        } label: {
            Text(lens == .ultraWide ? "0.5" : "1x")
                .font(.system(size: isSelected ? 13 : 12, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .yellow : .white)
                .frame(width: isSelected ? 38 : 34, height: isSelected ? 38 : 34)
                .background(Color.black.opacity(isSelected ? 0.5 : 0.35))
                .clipShape(Circle())
        }
        .disabled(recordingService.isRecording)
        .opacity(recordingService.isRecording ? 0.45 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var subtitleModeToggle: some View {
        HStack(spacing: 0) {
            subtitleModeSegment(.speech, icon: "waveform")
            subtitleModeSegment(.aiVision, icon: "eye")
        }
        .frame(height: 36)
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
        .disabled(recordingService.isRecording)
        .opacity(recordingService.isRecording ? 0.45 : 1.0)
    }

    private func subtitleModeSegment(_ mode: SubtitleMode, icon: String) -> some View {
        let isSelected = settings.subtitleMode == mode
        return Button {
            settings.subtitleMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.white.opacity(0.25) : Color.clear)
                .clipShape(Capsule())
        }
    }

    private var savedToast: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(L10n.videoSavedMessage)
                .foregroundColor(.white)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.7))
        .clipShape(Capsule())
    }

    // MARK: - Subtitle text

    /// Whether speech subtitles are translated (setting on, languages differ, iOS 18+)
    private var translationActive: Bool {
        if #available(iOS 18.0, *) {
            return settings.isSpeechTranslationActive
        }
        return false
    }

    private var previewSubtitleText: String {
        if settings.subtitleMode == .aiVision {
            return aiVisionService.displayText
        }
        if translationActive {
            return translationService.displayText
        }
        return speechService.displayText
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
        recordingService.translationService = translationService
        recordingService.subtitleMode = settings.subtitleMode
        recordingService.speechTranslationActive = translationActive

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
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            Task {
                // Unlock capture connection rotation
                cameraService.isRecordingActive = false

                // Stop recording first (while subtitles still active), then clear subtitles
                if let url = await recordingService.stopRecording() {
                    let success = await VideoRecordingService.saveToPhotoLibrary(url: url)
                    await MainActor.run {
                        if success {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showSavedToast = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showSavedToast = false
                                }
                            }
                        } else {
                            savedSuccess = false
                            showSavedAlert = true
                        }
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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // Lock capture connection rotation to prevent buffer dimension changes
            cameraService.isRecordingActive = true

            recordingService.letterboxColor = settings.letterboxColor
            recordingService.subtitleMode = settings.subtitleMode
            recordingService.speechTranslationActive = translationActive
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
