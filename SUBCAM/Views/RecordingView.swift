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

    @State private var lastThumbnail: UIImage?
    @State private var showStyleDrawer = false

    /// Non-essential chrome fades out while recording, camera-app style.
    private var isRecording: Bool { recordingService.isRecording }

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

            // Subtitle overlay (live preview, also before recording starts)
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

            // Watermark preview (free tier; mirrors the burned-in watermark)
            if !settings.isProUnlocked {
                VStack {
                    HStack {
                        Spacer()
                        Text("#SUBCAM")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)
                    }
                    Spacer()
                }
                .padding(.top, cameraService.isLandscape ? 64 : 110)
                .padding(.trailing, 14)
                .allowsHitTesting(false)
            }

            // Controls overlay
            if cameraService.isLandscape {
                landscapeControls
            } else {
                portraitControls
            }

            // Saved toast (top center)
            if showSavedToast {
                VStack {
                    savedToast
                        .padding(.top, cameraService.isLandscape ? 46 : 92)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Subtitle style drawer
            if showStyleDrawer {
                // Transparent outside-tap catcher (no scrim — the preview stays visible)
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { closeStyleDrawer() }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SubtitleStyleDrawer(settings: settings)
                        .frame(maxWidth: 420)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
                // Speech captions run continuously so the preview is never blank
                speechService.startRecognition()
            } else {
                speechService.stopRecognition()
                translationService.clear()
            }
        }
        .onChange(of: settings.aiProvider) { _, _ in
            aiVisionService.updateProvider()
        }
        .onChange(of: settings.aiModels) { _, _ in
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
                }
            )
        }
    }

    // MARK: - Portrait controls

    private var portraitControls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    subtitleModeToggle
                    translationQuickButton
                }
                .padding(.leading, 20)

                Spacer()

                settingsButton
                    .padding(.trailing, 20)
            }
            .padding(.top, 60)
            .hiddenWhileRecording(isRecording)

            if recordingService.isRecording {
                recordingTimerBadge
                    .padding(.top, 8)
            }

            Spacer()

            if !isRecording && settings.subtitleMode == .aiVision {
                aiSubtitleHintPill
                    .padding(.bottom, 12)
            }

            zoomChip
                .opacity(showZoomChip ? 1 : 0)
                .padding(.bottom, 10)

            lensChips
                .padding(.bottom, 14)
                .hiddenWhileRecording(isRecording)

            lookBar
                .padding(.bottom, 16)
                .hiddenWhileRecording(isRecording)

            shutterRow
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
        }
    }

    // MARK: - Landscape controls

    private var landscapeControls: some View {
        HStack(spacing: 0) {
            // Left rail: subtitle mode, translation, settings
            VStack(alignment: .leading, spacing: 12) {
                settingsButton
                subtitleModeToggle
                translationQuickButton
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.top, 16)
            .hiddenWhileRecording(isRecording)

            Spacer()

            // Center: timer on top, AI hint at the bottom
            VStack {
                if recordingService.isRecording {
                    recordingTimerBadge
                }
                Spacer()
                if !isRecording && settings.subtitleMode == .aiVision {
                    aiSubtitleHintPill
                }
                zoomChip
                    .opacity(showZoomChip ? 1 : 0)
                    .padding(.top, 10)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)

            Spacer()

            // Right rail: look bar, lens chips, shutter column
            HStack(spacing: 14) {
                lookBarVertical
                    .hiddenWhileRecording(isRecording)

                lensChipsVertical
                    .hiddenWhileRecording(isRecording)

                VStack(spacing: 18) {
                    Spacer()
                    thumbnailButton
                        .hiddenWhileRecording(isRecording)
                    recordButton
                    styleButton
                        .hiddenWhileRecording(isRecording)
                    Spacer()
                }
            }
            .padding(.trailing, 24)
        }
    }

    // MARK: - Shutter row

    private var shutterRow: some View {
        HStack {
            thumbnailButton
                .hiddenWhileRecording(isRecording)

            Spacer()

            recordButton

            Spacer()

            styleButton
                .hiddenWhileRecording(isRecording)
        }
    }

    private var thumbnailButton: some View {
        Button {
            openPhotosApp()
        } label: {
            Group {
                if let thumbnail = lastThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.black.opacity(0.45)
                        Image(systemName: "photo")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
        }
        .accessibilityLabel(L10n.recentVideo)
    }

    private var styleButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showStyleDrawer.toggle()
            }
        } label: {
            Text("Aa")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(showStyleDrawer ? .yellow : .white)
                .frame(width: 46, height: 46)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .accessibilityLabel(L10n.subtitleStyle)
    }

    // MARK: - Look bar

    private var isStandardLook: Bool {
        !settings.cinemaScope && !settings.cinematicMode && !settings.monochromeMode
    }

    private var lookBar: some View {
        HStack(spacing: 4) {
            lookChips
        }
        .padding(.horizontal, 6)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
    }

    private var lookBarVertical: some View {
        VStack(spacing: 4) {
            lookChips
        }
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var lookChips: some View {
        lookChip("STD", isActive: isStandardLook, label: L10n.lookStandard) {
            settings.cinemaScope = false
            settings.cinematicMode = false
            settings.monochromeMode = false
        }
        lookChip("SCOPE", isActive: settings.cinemaScope, label: L10n.lookScope) {
            settings.cinemaScope.toggle()
        }
        lookChip("CINE", isActive: settings.cinematicMode, label: L10n.lookCinematic) {
            settings.cinematicMode.toggle()
        }
        lookChip("MONO", isActive: settings.monochromeMode, label: L10n.lookMono) {
            settings.monochromeMode.toggle()
        }
    }

    private func lookChip(_ code: String, isActive: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(code)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? .yellow : .white.opacity(0.7))
                .frame(minWidth: 52)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .animation(.easeOut(duration: 0.15), value: isActive)
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

    private var aiSubtitleHintPill: some View {
        Text(L10n.aiSubtitleRecordingHint)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var subtitleModeToggle: some View {
        HStack(spacing: 0) {
            subtitleModeSegment(.speech, icon: "waveform", label: L10n.subtitleModeVoiceShort)
            subtitleModeSegment(.aiVision, icon: "eye", label: L10n.subtitleModeAIShort)
        }
        .frame(height: 36)
        .background(Color.black.opacity(0.4))
        .clipShape(Capsule())
    }

    private func subtitleModeSegment(_ mode: SubtitleMode, icon: String, label: String) -> some View {
        let isSelected = settings.subtitleMode == mode
        return Button {
            settings.subtitleMode = mode
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isSelected ? Color.white.opacity(0.25) : Color.clear)
            .clipShape(Capsule())
        }
    }

    /// Quick translation cycle (off → EN → JA → off). Speech mode, iOS 18+ only.
    @ViewBuilder
    private var translationQuickButton: some View {
        if settings.subtitleMode == .speech {
            if #available(iOS 18.0, *) {
                let isActive = settings.speechTranslation != .off
                Button {
                    cycleSpeechTranslation()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 14, weight: .semibold))
                        if let code = translationShortCode {
                            Text(code)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundColor(isActive ? .yellow : .white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
                }
                .accessibilityLabel(L10n.speechTranslationShort)
            }
        }
    }

    private var translationShortCode: String? {
        switch settings.speechTranslation {
        case .off: return nil
        case .en: return "EN"
        case .ja: return "JA"
        }
    }

    private func cycleSpeechTranslation() {
        switch settings.speechTranslation {
        case .off: settings.speechTranslation = .en
        case .en: settings.speechTranslation = .ja
        case .ja: settings.speechTranslation = .off
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

    private func closeStyleDrawer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showStyleDrawer = false
        }
    }

    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }

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

        // Live caption preview: speech recognition runs from the moment the
        // camera opens, not only while recording. Safe to keep running because
        // SpeechRecognitionService auto-restarts before the 60s task limit.
        if settings.subtitleMode == .speech {
            speechService.startRecognition()
        }
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
                    if success {
                        // Build the shutter-row thumbnail from the temp file before
                        // it is deleted — the app has add-only photo access, so the
                        // saved asset can never be read back from the library.
                        let thumbnail = await makeThumbnail(from: url)
                        await MainActor.run {
                            if let thumbnail {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    lastThumbnail = thumbnail
                                }
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showSavedToast = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showSavedToast = false
                                }
                            }
                        }
                    } else {
                        await MainActor.run {
                            savedSuccess = false
                            showSavedAlert = true
                        }
                    }
                    try? FileManager.default.removeItem(at: url)
                }
                // Speech recognition keeps running so the preview caption stays live.
                if settings.subtitleMode == .aiVision {
                    aiVisionService.stop()
                }
            }
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // Lock capture connection rotation to prevent buffer dimension changes
            cameraService.isRecordingActive = true

            closeStyleDrawer()

            recordingService.letterboxColor = settings.letterboxColor
            recordingService.subtitleMode = settings.subtitleMode
            recordingService.speechTranslationActive = translationActive
            recordingService.startRecording()
            if settings.subtitleMode == .speech {
                // Already running from the live preview in the normal case
                if !speechService.isRecognizing {
                    speechService.startRecognition()
                }
            } else {
                aiVisionService.start()
            }
        }
    }

    /// First-frame thumbnail of a just-recorded clip, held in memory only.
    private func makeThumbnail(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Failed to generate thumbnail: \(error)")
            return nil
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Recording fade

private extension View {
    /// Fades and disables non-essential chrome while recording, matching the
    /// stock camera app where only the timer and shutter remain.
    func hiddenWhileRecording(_ isRecording: Bool) -> some View {
        self
            .opacity(isRecording ? 0 : 1)
            .disabled(isRecording)
            .allowsHitTesting(!isRecording)
            .animation(.easeInOut(duration: 0.25), value: isRecording)
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
