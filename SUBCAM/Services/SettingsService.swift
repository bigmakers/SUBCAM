import Foundation
import AVFoundation
import UIKit

// MARK: - App Language

enum AppLanguage: String, CaseIterable {
    case ja = "ja"
    case en = "en"

    var displayName: String {
        switch self {
        case .ja: return "日本語"
        case .en: return "English"
        }
    }
}

/// Shorthand for current language check
private var isEN: Bool { SettingsService.shared.appLanguage == .en }

// MARK: - Orientation

enum OrientationLock: String, CaseIterable {
    case auto = "auto"
    case portrait = "portrait"
    case landscape = "landscape"

    var displayName: String {
        switch self {
        case .auto: return isEN ? "Auto" : "自動"
        case .portrait: return isEN ? "Portrait Lock" : "縦固定"
        case .landscape: return isEN ? "Landscape Lock" : "横固定"
        }
    }
}

// MARK: - Camera

enum CameraLens: String, CaseIterable {
    case wide = "wide"
    case ultraWide = "ultraWide"

    var displayName: String {
        switch self {
        case .wide: return isEN ? "Wide (1x)" : "広角 (1x)"
        case .ultraWide: return isEN ? "Ultra Wide (0.5x)" : "超広角 (0.5x)"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .wide: return .builtInWideAngleCamera
        case .ultraWide: return .builtInUltraWideCamera
        }
    }
}

// MARK: - Subtitle

enum SubtitleSize: String, CaseIterable {
    case standard = "standard"
    case large = "large"

    var displayName: String {
        switch self {
        case .standard: return isEN ? "Standard" : "標準"
        case .large: return isEN ? "Large (2x)" : "大 (2x)"
        }
    }

    var scale: CGFloat {
        switch self {
        case .standard: return 1.0
        case .large: return 2.0
        }
    }
}

enum SubtitleFont: String, CaseIterable {
    case system = "system"
    case rounded = "rounded"
    case serif = "serif"
    case hiraginoSans = "hiraginoSans"
    case hiraginoMincho = "hiraginoMincho"

    var displayName: String {
        switch self {
        case .system: return isEN ? "Gothic (Default)" : "ゴシック（デフォルト）"
        case .rounded: return isEN ? "Rounded" : "丸ゴシック"
        case .serif: return isEN ? "Serif" : "明朝（欧文セリフ）"
        case .hiraginoSans: return isEN ? "Hiragino Sans" : "ヒラギノ角ゴ"
        case .hiraginoMincho: return isEN ? "Hiragino Mincho" : "ヒラギノ明朝"
        }
    }

    /// UIFont for recording renderer — bold weight (standard mode)
    func uiFont(size: CGFloat, bold: Bool = true) -> UIFont {
        switch self {
        case .system:
            return UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .rounded:
            let desc = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular).fontDescriptor
            if let rounded = desc.withDesign(.rounded) {
                return UIFont(descriptor: rounded, size: size)
            }
            return UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .serif:
            let desc = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular).fontDescriptor
            if let serif = desc.withDesign(.serif) {
                return UIFont(descriptor: serif, size: size)
            }
            return UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .hiraginoSans:
            return UIFont(name: bold ? "HiraginoSans-W6" : "HiraginoSans-W3", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .hiraginoMincho:
            return UIFont(name: bold ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size)
                ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
    }
}

enum SubtitlePosition: String, CaseIterable {
    case top = "top"
    case center = "center"
    case bottom = "bottom"
    case danmaku = "danmaku"

    var displayName: String {
        switch self {
        case .top: return isEN ? "Top" : "上部"
        case .center: return isEN ? "Center" : "中央"
        case .bottom: return isEN ? "Bottom" : "下部"
        case .danmaku: return isEN ? "Danmaku" : "弾幕"
        }
    }
}

enum SubtitleMode: String, CaseIterable {
    case speech = "speech"
    case aiVision = "aiVision"

    var displayName: String {
        switch self {
        case .speech: return isEN ? "Speech" : "音声字幕"
        case .aiVision: return isEN ? "AI Vision" : "AI字幕"
        }
    }
}

// MARK: - Video Quality

enum VideoQuality: String, CaseIterable {
    case hd1080p30 = "1080p30"
    case hd1080p60 = "1080p60"
    case uhd4K30 = "4K30"
    case uhd4K60 = "4K60"

    var displayName: String {
        switch self {
        case .hd1080p30: return "1080p 30fps"
        case .hd1080p60: return "1080p 60fps"
        case .uhd4K30: return "4K 30fps"
        case .uhd4K60: return "4K 60fps"
        }
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .hd1080p30, .hd1080p60: return .hd1920x1080
        case .uhd4K30, .uhd4K60: return .hd4K3840x2160
        }
    }

    var frameRate: Double {
        switch self {
        case .hd1080p30, .uhd4K30: return 30.0
        case .hd1080p60, .uhd4K60: return 60.0
        }
    }

    var bitRate: Int {
        switch self {
        case .hd1080p30: return 10_000_000
        case .hd1080p60: return 16_000_000
        case .uhd4K30: return 30_000_000
        case .uhd4K60: return 50_000_000
        }
    }
}

enum ExposureBias: String, CaseIterable {
    case minus2 = "-2"
    case minus1 = "-1"
    case zero = "0"
    case plus1 = "+1"
    case plus2 = "+2"

    var displayName: String {
        switch self {
        case .minus2: return "-2"
        case .minus1: return isEN ? "-1 (Default)" : "-1 (デフォルト)"
        case .zero: return "±0"
        case .plus1: return "+1"
        case .plus2: return "+2"
        }
    }

    var evValue: Float {
        switch self {
        case .minus2: return -2.0
        case .minus1: return -1.0
        case .zero: return 0.0
        case .plus1: return 1.0
        case .plus2: return 2.0
        }
    }
}

// MARK: - Letterbox

enum LetterboxColor: String, CaseIterable {
    case black = "black"
    case turquoise = "turquoise"
    case orange = "orange"
    case red = "red"
    case beige = "beige"
    case white = "white"

    var displayName: String {
        switch self {
        case .black: return "Black"
        case .turquoise: return "Turquoise"
        case .orange: return "Orange"
        case .red: return "Red"
        case .beige: return "Beige"
        case .white: return "White"
        }
    }

    var rgbComponents: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .black: return (0, 0, 0)
        case .turquoise: return (0.32, 0.76, 0.74)
        case .orange: return (0.93, 0.55, 0.22)
        case .red: return (0.78, 0.18, 0.18)
        case .beige: return (0.91, 0.87, 0.78)
        case .white: return (1.0, 1.0, 1.0)
        }
    }

    /// Whether subtitle text should be dark for readability
    var usesDarkText: Bool {
        switch self {
        case .beige, .white: return true
        default: return false
        }
    }
}

// MARK: - AI

enum AIResponseStyle: String, CaseIterable {
    case word = "word"
    case sentence = "sentence"

    var displayName: String {
        switch self {
        case .word: return isEN ? "Word / Phrase" : "単語・フレーズ"
        case .sentence: return isEN ? "Sentence" : "文章"
        }
    }

    var prompt: String {
        switch self {
        case .word:
            return isEN
                ? "Describe what you see in this image in a short word or phrase (under 10 characters). No explanations or sentences."
                : "この画像に写っているものを日本語で短い単語やフレーズ（10文字以内）で1つだけ答えてください。説明や文章は不要です。"
        case .sentence:
            return isEN
                ? "Describe the situation in this image in one concise sentence (under 30 characters)."
                : "この画像に写っている状況を日本語で1文（30文字以内）で簡潔に説明してください。"
        }
    }
}

enum AIProvider: String, CaseIterable {
    case gemini = "gemini"
    case claude = "claude"
    case openai = "openai"
    case localLLM = "localLLM"

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        case .openai: return "ChatGPT"
        case .localLLM: return isEN ? "Local LLM" : "ローカルLLM"
        }
    }

    var keychainService: String? {
        switch self {
        case .gemini: return KeychainService.geminiKey
        case .claude: return KeychainService.claudeKey
        case .openai: return KeychainService.openaiKey
        case .localLLM: return nil
        }
    }
}

// MARK: - Speech Language

struct SpeechLanguage: Identifiable, Hashable {
    let id: String  // locale identifier
    let displayName: String

    static let supported: [SpeechLanguage] = [
        SpeechLanguage(id: "ja-JP", displayName: "日本語"),
        SpeechLanguage(id: "en-US", displayName: "English (US)"),
        SpeechLanguage(id: "en-GB", displayName: "English (UK)"),
        SpeechLanguage(id: "zh-Hans", displayName: "中文 (简体)"),
        SpeechLanguage(id: "zh-Hant", displayName: "中文 (繁體)"),
        SpeechLanguage(id: "ko-KR", displayName: "한국어"),
        SpeechLanguage(id: "fr-FR", displayName: "Français"),
        SpeechLanguage(id: "de-DE", displayName: "Deutsch"),
        SpeechLanguage(id: "es-ES", displayName: "Español"),
        SpeechLanguage(id: "pt-BR", displayName: "Português"),
        SpeechLanguage(id: "th-TH", displayName: "ไทย"),
    ]
}

// MARK: - Localized UI Strings

/// Centralized UI strings for SettingsView and RecordingView
enum L10n {
    // Navigation
    static var settings: String { isEN ? "Settings" : "設定" }
    static var done: String { isEN ? "Done" : "完了" }

    // Pro
    static var proDescription: String { isEN ? "Unlock quality, HDR & exposure settings" : "画質・HDR・露出補正の設定を解除" }
    static var purchase: String { isEN ? "Purchase" : "で購入" }
    static var restorePurchase: String { isEN ? "Restore Purchase" : "購入を復元" }

    // Section headers
    static var orientation: String { isEN ? "Orientation" : "画面の向き" }
    static var camera: String { isEN ? "Camera" : "カメラ" }
    static var look: String { isEN ? "Look" : "ルック" }
    static var letterbox: String { isEN ? "Letterbox" : "レターボックス" }
    static var videoQuality: String { isEN ? "Video Quality" : "映像品質" }
    static var subtitle: String { isEN ? "Subtitle" : "字幕" }
    static var subtitleFontHeader: String { isEN ? "Font" : "フォント" }
    static var speechLanguage: String { isEN ? "Speech Language" : "音声認識の言語" }
    static var aiSettings: String { isEN ? "AI Settings" : "AI設定" }
    static var apiKey: String { isEN ? "API Key" : "APIキー" }
    static var endpoint: String { isEN ? "Endpoint" : "エンドポイント" }
    static var language: String { isEN ? "Language" : "言語" }

    // Format options
    static var standardFrame: String { isEN ? "Standard" : "Standard — 標準フレーム" }
    static var scopeFrame: String { isEN ? "Scope — CinemaScope" : "Scope — シネスコ風" }

    // Look options
    static var natural: String { isEN ? "Natural" : "Natural — ナチュラル" }
    static var cinematic: String { isEN ? "Cinematic" : "Cinematic — 映画風トーン" }
    static var colorMode: String { isEN ? "Color" : "Color — カラー表現" }
    static var monoMode: String { isEN ? "Mono" : "Mono — モノクロ" }

    // HDR
    static var hdrRecording: String { isEN ? "HDR Recording" : "HDR撮影" }

    // API Key
    static var save: String { isEN ? "Save" : "保存" }
    static var delete: String { isEN ? "Delete" : "削除" }
    static var apiKeyConfigured: String { isEN ? "API Key configured" : "APIキー設定済み" }

    // Alerts
    static var saveComplete: String { isEN ? "Saved" : "保存完了" }
    static var saveFailed: String { isEN ? "Save Failed" : "保存失敗" }
    static var videoSavedMessage: String { isEN ? "Video saved to Photo Library" : "ビデオがフォトライブラリに保存されました" }
    static var videoSaveFailedMessage: String { isEN ? "Failed to save video" : "ビデオの保存に失敗しました" }
}

// MARK: - Settings Service

class SettingsService: ObservableObject {
    static let shared = SettingsService()

    @Published var appLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage") }
    }

    @Published var orientationLock: OrientationLock {
        didSet { UserDefaults.standard.set(orientationLock.rawValue, forKey: "orientationLock") }
    }

    @Published var cameraLens: CameraLens {
        didSet { UserDefaults.standard.set(cameraLens.rawValue, forKey: "cameraLens") }
    }

    @Published var subtitleSize: SubtitleSize {
        didSet { UserDefaults.standard.set(subtitleSize.rawValue, forKey: "subtitleSize") }
    }

    @Published var subtitleFont: SubtitleFont {
        didSet { UserDefaults.standard.set(subtitleFont.rawValue, forKey: "subtitleFont") }
    }

    @Published var speechLanguageId: String {
        didSet { UserDefaults.standard.set(speechLanguageId, forKey: "speechLanguageId") }
    }

    @Published var videoQuality: VideoQuality {
        didSet { UserDefaults.standard.set(videoQuality.rawValue, forKey: "videoQuality") }
    }

    @Published var hdrEnabled: Bool {
        didSet { UserDefaults.standard.set(hdrEnabled, forKey: "hdrEnabled") }
    }

    @Published var exposureBias: ExposureBias {
        didSet { UserDefaults.standard.set(exposureBias.rawValue, forKey: "exposureBias") }
    }

    @Published var monochromeMode: Bool {
        didSet { UserDefaults.standard.set(monochromeMode, forKey: "monochromeMode") }
    }

    @Published var cinemaScope: Bool {
        didSet { UserDefaults.standard.set(cinemaScope, forKey: "cinemaScope") }
    }

    @Published var cinematicMode: Bool {
        didSet { UserDefaults.standard.set(cinematicMode, forKey: "cinematicMode") }
    }

    @Published var subtitlePosition: SubtitlePosition {
        didSet { UserDefaults.standard.set(subtitlePosition.rawValue, forKey: "subtitlePosition") }
    }

    @Published var letterboxColor: LetterboxColor {
        didSet { UserDefaults.standard.set(letterboxColor.rawValue, forKey: "letterboxColor") }
    }

    @Published var subtitleMode: SubtitleMode {
        didSet { UserDefaults.standard.set(subtitleMode.rawValue, forKey: "subtitleMode") }
    }

    @Published var aiProvider: AIProvider {
        didSet { UserDefaults.standard.set(aiProvider.rawValue, forKey: "aiProvider") }
    }

    @Published var aiResponseStyle: AIResponseStyle {
        didSet { UserDefaults.standard.set(aiResponseStyle.rawValue, forKey: "aiResponseStyle") }
    }

    @Published var localLLMEndpoint: String {
        didSet { UserDefaults.standard.set(localLLMEndpoint, forKey: "localLLMEndpoint") }
    }

    @Published var isProUnlocked: Bool {
        didSet { UserDefaults.standard.set(isProUnlocked, forKey: "isProUnlocked") }
    }

    var speechLanguage: SpeechLanguage {
        SpeechLanguage.supported.first { $0.id == speechLanguageId }
            ?? SpeechLanguage.supported[0]
    }

    private init() {
        let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.ja.rawValue
        self.appLanguage = AppLanguage(rawValue: savedLanguage) ?? .ja

        let savedOrientation = UserDefaults.standard.string(forKey: "orientationLock") ?? OrientationLock.auto.rawValue
        self.orientationLock = OrientationLock(rawValue: savedOrientation) ?? .auto

        let savedLens = UserDefaults.standard.string(forKey: "cameraLens") ?? CameraLens.wide.rawValue
        self.cameraLens = CameraLens(rawValue: savedLens) ?? .wide

        let savedSize = UserDefaults.standard.string(forKey: "subtitleSize") ?? SubtitleSize.standard.rawValue
        self.subtitleSize = SubtitleSize(rawValue: savedSize) ?? .standard

        let savedFont = UserDefaults.standard.string(forKey: "subtitleFont") ?? SubtitleFont.system.rawValue
        self.subtitleFont = SubtitleFont(rawValue: savedFont) ?? .system

        let savedLang = UserDefaults.standard.string(forKey: "speechLanguageId") ?? "ja-JP"
        self.speechLanguageId = savedLang

        let savedQuality = UserDefaults.standard.string(forKey: "videoQuality") ?? VideoQuality.hd1080p30.rawValue
        self.videoQuality = VideoQuality(rawValue: savedQuality) ?? .hd1080p30

        self.hdrEnabled = UserDefaults.standard.object(forKey: "hdrEnabled") as? Bool ?? false

        let savedExposure = UserDefaults.standard.string(forKey: "exposureBias") ?? ExposureBias.minus1.rawValue
        self.exposureBias = ExposureBias(rawValue: savedExposure) ?? .minus1

        self.monochromeMode = UserDefaults.standard.object(forKey: "monochromeMode") as? Bool ?? false

        let savedPosition = UserDefaults.standard.string(forKey: "subtitlePosition") ?? SubtitlePosition.bottom.rawValue
        self.subtitlePosition = SubtitlePosition(rawValue: savedPosition) ?? .bottom

        self.cinemaScope = UserDefaults.standard.object(forKey: "cinemaScope") as? Bool ?? false
        self.cinematicMode = UserDefaults.standard.object(forKey: "cinematicMode") as? Bool ?? false

        let savedLetterbox = UserDefaults.standard.string(forKey: "letterboxColor") ?? LetterboxColor.black.rawValue
        self.letterboxColor = LetterboxColor(rawValue: savedLetterbox) ?? .black

        let savedSubtitleMode = UserDefaults.standard.string(forKey: "subtitleMode") ?? SubtitleMode.speech.rawValue
        self.subtitleMode = SubtitleMode(rawValue: savedSubtitleMode) ?? .speech

        let savedAIProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? AIProvider.gemini.rawValue
        self.aiProvider = AIProvider(rawValue: savedAIProvider) ?? .gemini

        let savedResponseStyle = UserDefaults.standard.string(forKey: "aiResponseStyle") ?? AIResponseStyle.word.rawValue
        self.aiResponseStyle = AIResponseStyle(rawValue: savedResponseStyle) ?? .word

        self.localLLMEndpoint = UserDefaults.standard.string(forKey: "localLLMEndpoint") ?? ""

        self.isProUnlocked = UserDefaults.standard.object(forKey: "isProUnlocked") as? Bool ?? false
    }
}
