import Foundation
import CoreMedia
import CoreVideo
import CoreImage
import UIKit

final class AIVisionService: ObservableObject, @unchecked Sendable {

    // Thread-safe current text for subtitle renderer (read from video queue)
    private let textLock = NSLock()
    private var _currentText: String = ""
    var currentText: String {
        get { textLock.lock(); defer { textLock.unlock() }; return _currentText }
        set { textLock.lock(); _currentText = newValue; textLock.unlock() }
    }

    // Published text for UI display (main thread only)
    @Published var displayText: String = ""
    @Published var isActive: Bool = false

    // Throttling
    private var lastCaptureTime: CFTimeInterval = 0
    private let captureInterval: CFTimeInterval = 2.0

    // Processing
    private let processingQueue = DispatchQueue(label: "com.subcam.aiVision.queue")
    private var isProcessing = false
    private var currentProvider: VisionAIProvider?

    // Shared CIContext for image conversion
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func start() {
        updateProvider()
        lastCaptureTime = 0
        isProcessing = false
        DispatchQueue.main.async {
            self.isActive = true
        }
    }

    func stop() {
        DispatchQueue.main.async {
            self.isActive = false
            self.displayText = ""
        }
        currentText = ""
        isProcessing = false
    }

    func updateProvider() {
        let settings = SettingsService.shared
        let provider = settings.aiProvider

        switch provider {
        case .gemini:
            if let key = KeychainService.load(service: KeychainService.geminiKey), !key.isEmpty {
                currentProvider = GeminiVisionProvider(apiKey: key)
            } else {
                currentProvider = nil
            }
        case .claude:
            if let key = KeychainService.load(service: KeychainService.claudeKey), !key.isEmpty {
                currentProvider = ClaudeVisionProvider(apiKey: key)
            } else {
                currentProvider = nil
            }
        case .openai:
            if let key = KeychainService.load(service: KeychainService.openaiKey), !key.isEmpty {
                currentProvider = OpenAIVisionProvider(apiKey: key)
            } else {
                currentProvider = nil
            }
        case .localLLM:
            let endpoint = settings.localLLMEndpoint
            if !endpoint.isEmpty {
                currentProvider = LocalLLMVisionProvider(endpoint: endpoint)
            } else {
                currentProvider = nil
            }
        }
    }

    func processVideoBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isActive else { return }

        let now = CACurrentMediaTime()
        guard now - lastCaptureTime >= captureInterval else { return }
        lastCaptureTime = now

        // Don't queue if already processing
        guard !isProcessing else { return }
        isProcessing = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessing = false
            return
        }

        // Convert to JPEG on processing queue
        processingQueue.async { [weak self] in
            guard let self else { return }

            guard let jpegData = self.convertToJPEG(pixelBuffer: pixelBuffer) else {
                self.isProcessing = false
                return
            }

            guard let provider = self.currentProvider else {
                let msg = SettingsService.shared.appLanguage == .en ? "Please set API key" : "APIキーを設定してください"
                self.updateText(msg)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.clearText()
                }
                self.isProcessing = false
                return
            }

            Task {
                do {
                    let prompt = SettingsService.shared.aiResponseStyle.prompt
                    let result = try await provider.analyze(imageData: jpegData, prompt: prompt)
                    self.updateText(result)
                } catch {
                    let errorMsg = "AI: \(error.localizedDescription)"
                    self.updateText(errorMsg)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if self.displayText == errorMsg {
                            self.clearText()
                        }
                    }
                }
                self.isProcessing = false
            }
        }
    }

    private func updateText(_ text: String) {
        currentText = text
        DispatchQueue.main.async {
            self.displayText = text
        }
    }

    private func clearText() {
        currentText = ""
        DispatchQueue.main.async {
            self.displayText = ""
        }
    }

    private func convertToJPEG(pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let originalWidth = ciImage.extent.width
        let originalHeight = ciImage.extent.height

        // Resize to 512px wide
        let targetWidth: CGFloat = 512
        let scale = targetWidth / originalWidth
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let targetHeight = originalHeight * scale
        guard let cgImage = Self.ciContext.createCGImage(scaledImage, from: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.7)
    }
}
