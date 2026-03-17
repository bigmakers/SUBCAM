import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsService.shared
    @StateObject private var store = StoreService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyInput: String = ""
    @State private var hasAPIKey: Bool = false
    var onVideoQualityChanged: ((VideoQuality) -> Void)?
    var onHDRChanged: ((Bool) -> Void)?
    var onExposureChanged: ((Float) -> Void)?
    var onCinemaScopeChanged: ((Bool) -> Void)?
    var onCinematicModeChanged: ((Bool) -> Void)?
    var onLensChanged: ((CameraLens) -> Void)?

    var body: some View {
        NavigationView {
            List {
                // MARK: - Language
                Section(L10n.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Button {
                            settings.appLanguage = lang
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if settings.appLanguage == lang {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                // MARK: - Pro purchase (shown when not unlocked)
                if !settings.isProUnlocked {
                    Section {
                        VStack(spacing: 12) {
                            Text("SUBCAM Pro")
                                .font(.headline)
                            Text(L10n.proDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button {
                                Task { await store.purchasePro() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if store.isPurchasing {
                                        ProgressView()
                                    } else {
                                        Text(store.proProduct?.displayPrice ?? "¥100")
                                            .fontWeight(.semibold)
                                        Text(L10n.purchase)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isPurchasing)

                            Button(L10n.restorePurchase) {
                                Task { await store.restorePurchases() }
                            }
                            .font(.caption)
                            .disabled(store.isPurchasing)

                            if let error = store.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                }

                // MARK: - Orientation
                Section(L10n.orientation) {
                    ForEach(OrientationLock.allCases, id: \.self) { lock in
                        Button {
                            settings.orientationLock = lock
                            applyOrientationLock(lock)
                        } label: {
                            settingRow(
                                icon: lock == .portrait ? "rectangle.portrait" : lock == .landscape ? "rectangle" : "rectangle.2.swap",
                                text: lock.displayName,
                                isSelected: settings.orientationLock == lock
                            )
                        }
                    }
                }

                // MARK: - Camera (Lens + Format)
                Section(L10n.camera) {
                    ForEach(CameraLens.allCases, id: \.self) { lens in
                        Button {
                            settings.cameraLens = lens
                            onLensChanged?(lens)
                        } label: {
                            settingRow(
                                icon: lens == .ultraWide ? "camera.on.rectangle" : "camera",
                                text: lens.displayName,
                                isSelected: settings.cameraLens == lens
                            )
                        }
                    }

                    Divider()

                    Button {
                        settings.cinemaScope = false
                        onCinemaScopeChanged?(false)
                    } label: {
                        settingRow(icon: "rectangle.portrait", text: L10n.standardFrame, isSelected: !settings.cinemaScope)
                    }

                    Button {
                        settings.cinemaScope = true
                        onCinemaScopeChanged?(true)
                    } label: {
                        settingRow(icon: "film.stack", text: L10n.scopeFrame, isSelected: settings.cinemaScope)
                    }
                }

                // MARK: - Look (Style + Color)
                Section(L10n.look) {
                    Button {
                        settings.cinematicMode = false
                        onCinematicModeChanged?(false)
                    } label: {
                        settingRow(icon: "camera", text: L10n.natural, isSelected: !settings.cinematicMode)
                    }

                    Button {
                        settings.cinematicMode = true
                        onCinematicModeChanged?(true)
                    } label: {
                        settingRow(icon: "camera.filters", text: L10n.cinematic, isSelected: settings.cinematicMode)
                    }

                    Divider()

                    Button {
                        settings.monochromeMode = false
                    } label: {
                        settingRow(icon: "circle.fill", text: L10n.colorMode, isSelected: !settings.monochromeMode)
                    }

                    Button {
                        settings.monochromeMode = true
                    } label: {
                        settingRow(icon: "circle.lefthalf.filled", text: L10n.monoMode, isSelected: settings.monochromeMode)
                    }
                }

                // MARK: - Letterbox (CinemaScope only)
                if settings.cinemaScope {
                    Section(L10n.letterbox) {
                        ForEach(LetterboxColor.allCases, id: \.self) { color in
                            Button {
                                settings.letterboxColor = color
                            } label: {
                                HStack {
                                    let rgb = color.rgbComponents
                                    Circle()
                                        .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle()
                                                .stroke(color == .black ? Color.gray.opacity(0.5) : Color.clear, lineWidth: 1)
                                        )
                                    Text(color.displayName)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if settings.letterboxColor == color {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                // MARK: - Video Quality (Pro: Quality + HDR + Exposure)
                Section {
                    ForEach(VideoQuality.allCases, id: \.self) { quality in
                        Button {
                            settings.videoQuality = quality
                            onVideoQualityChanged?(quality)
                        } label: {
                            HStack {
                                Text(quality.displayName)
                                    .foregroundColor(settings.isProUnlocked ? .primary : .secondary)
                                Spacer()
                                if settings.videoQuality == quality {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .disabled(!settings.isProUnlocked)
                    }

                    Divider()

                    Toggle(isOn: Binding(
                        get: { settings.hdrEnabled },
                        set: { newValue in
                            settings.hdrEnabled = newValue
                            onHDRChanged?(newValue)
                        }
                    )) {
                        Text(L10n.hdrRecording)
                            .foregroundColor(settings.isProUnlocked ? .primary : .secondary)
                    }
                    .disabled(!settings.isProUnlocked)

                    Divider()

                    ForEach(ExposureBias.allCases, id: \.self) { bias in
                        Button {
                            settings.exposureBias = bias
                            onExposureChanged?(bias.evValue)
                        } label: {
                            HStack {
                                Text(bias.displayName)
                                    .foregroundColor(settings.isProUnlocked ? .primary : .secondary)
                                Spacer()
                                if settings.exposureBias == bias {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .disabled(!settings.isProUnlocked)
                    }
                } header: {
                    HStack {
                        Text(L10n.videoQuality)
                        if !settings.isProUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                        }
                    }
                }

                // MARK: - Subtitle (Mode + Position + Size)
                Section(L10n.subtitle) {
                    ForEach(SubtitleMode.allCases, id: \.self) { mode in
                        Button {
                            settings.subtitleMode = mode
                        } label: {
                            settingRow(
                                icon: mode == .speech ? "waveform" : "eye",
                                text: mode.displayName,
                                isSelected: settings.subtitleMode == mode
                            )
                        }
                    }

                    Divider()

                    ForEach(SubtitlePosition.allCases, id: \.self) { position in
                        Button {
                            settings.subtitlePosition = position
                        } label: {
                            HStack {
                                Text(position.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if settings.subtitlePosition == position {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }

                    Divider()

                    ForEach(SubtitleSize.allCases, id: \.self) { size in
                        Button {
                            settings.subtitleSize = size
                        } label: {
                            HStack {
                                Text(size.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if settings.subtitleSize == size {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                // MARK: - Font
                Section(L10n.subtitleFontHeader) {
                    ForEach(SubtitleFont.allCases, id: \.self) { font in
                        Button {
                            settings.subtitleFont = font
                        } label: {
                            HStack {
                                Text(font.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if settings.subtitleFont == font {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                // MARK: - Speech Language (Speech mode only)
                if settings.subtitleMode == .speech {
                    Section(L10n.speechLanguage) {
                        ForEach(SpeechLanguage.supported) { lang in
                            Button {
                                settings.speechLanguageId = lang.id
                            } label: {
                                HStack {
                                    Text(lang.displayName)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if settings.speechLanguageId == lang.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                // MARK: - AI Settings (AI mode only)
                if settings.subtitleMode == .aiVision {
                    Section(L10n.aiSettings) {
                        ForEach(AIResponseStyle.allCases, id: \.self) { style in
                            Button {
                                settings.aiResponseStyle = style
                            } label: {
                                settingRow(
                                    icon: style == .word ? "textformat.size.smaller" : "text.alignleft",
                                    text: style.displayName,
                                    isSelected: settings.aiResponseStyle == style
                                )
                            }
                        }

                        Divider()

                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Button {
                                settings.aiProvider = provider
                                loadAPIKeyState()
                            } label: {
                                HStack {
                                    Text(provider.displayName)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if settings.aiProvider == provider {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }

                    // API key input
                    if let keychainId = settings.aiProvider.keychainService {
                        Section("\(settings.aiProvider.displayName) \(L10n.apiKey)") {
                            SecureField(L10n.apiKey, text: $apiKeyInput)
                                .textContentType(.password)
                                .autocapitalization(.none)

                            Button {
                                if !apiKeyInput.isEmpty {
                                    KeychainService.save(key: apiKeyInput, service: keychainId)
                                    hasAPIKey = true
                                    apiKeyInput = ""
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "key.fill")
                                    Text(L10n.save)
                                }
                            }
                            .disabled(apiKeyInput.isEmpty)

                            if hasAPIKey {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(L10n.apiKeyConfigured)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button(L10n.delete) {
                                        KeychainService.delete(service: keychainId)
                                        hasAPIKey = false
                                    }
                                    .foregroundColor(.red)
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    // Local LLM endpoint
                    if settings.aiProvider == .localLLM {
                        Section(L10n.endpoint) {
                            TextField("http://192.168.1.100:11434/v1/chat/completions", text: Binding(
                                get: { settings.localLLMEndpoint },
                                set: { settings.localLLMEndpoint = $0 }
                            ))
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .textContentType(.URL)
                        }
                    }
                }
            }
            .onAppear { loadAPIKeyState() }
            .navigationTitle(L10n.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.done) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func settingRow(icon: String, text: String, isSelected: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            Text(text)
                .foregroundColor(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
    }

    private func loadAPIKeyState() {
        if let keychainId = settings.aiProvider.keychainService {
            hasAPIKey = KeychainService.load(service: keychainId) != nil
        } else {
            hasAPIKey = false
        }
        apiKeyInput = ""
    }

    private func applyOrientationLock(_ lock: OrientationLock) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        // Request geometry update to apply the new orientation mask
        let geometryPreferences: UIWindowScene.GeometryPreferences.iOS
        switch lock {
        case .portrait:
            geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
        case .landscape:
            geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
        case .auto:
            geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .allButUpsideDown)
        }

        windowScene.requestGeometryUpdate(geometryPreferences) { error in
            print("Orientation update error: \(error)")
        }

        // Also trigger setNeedsUpdateOfSupportedInterfaceOrientations
        for window in windowScene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
