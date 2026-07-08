import Foundation
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleVisionProvider: VisionAIProvider {
    func analyze(imageData: Data, prompt: String) async throws -> String {
        // Step A: on-device Vision classification (iOS 17+, all devices)
        let handler = VNImageRequestHandler(data: imageData)
        let request = VNClassifyImageRequest()
        try handler.perform([request])

        let observations = request.results ?? []
        let filtered = observations.filter { $0.hasMinimumPrecision(0.5, forRecall: 0.5) }
        let candidates = (filtered.isEmpty ? observations.filter { $0.confidence > 0.3 } : filtered)
            .prefix(3)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }

        guard let topLabel = candidates.first else {
            let msg = SettingsService.shared.appLanguage == .en ? "Nothing recognized" : "認識できませんでした"
            throw VisionAIError.apiError(msg)
        }

        // Step B: Foundation Models polish (only when available on-device)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                do {
                    let style = SettingsService.shared.aiResponseStyle
                    let language = SettingsService.shared.appLanguage
                    let labelsList = candidates.joined(separator: ", ")

                    // Note: the `prompt` parameter is written for image-input models
                    // (Gemini/Claude/OpenAI); Foundation Models here only sees the
                    // Vision-classified labels as text, so it is intentionally ignored.
                    let instructions: String
                    switch style {
                    case .word:
                        instructions = language == .ja
                            ? "与えられた画像認識ラベルから、写っているものを表す短い単語やフレーズ（10文字以内）を日本語で1つだけ出力してください。説明は不要です。字幕テキストのみを出力してください。"
                            : "From the given image recognition labels, output only a short English word or phrase (a few words) describing what is shown. No explanations, output only the subtitle text."
                    case .sentence:
                        instructions = language == .ja
                            ? "与えられた画像認識ラベルから、写っている状況を表す簡潔な1文（30文字以内）を日本語で出力してください。説明は不要です。字幕テキストのみを出力してください。"
                            : "From the given image recognition labels, output only one concise short English sentence describing the situation. No explanations, output only the subtitle text."
                    }

                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(to: language == .ja ? "ラベル: \(labelsList)" : "Labels: \(labelsList)")
                    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        return text
                    }
                } catch {
                    // Guardrail violations, context errors, or an availability race:
                    // fall back to the raw Vision label rather than propagating.
                }
            }
        }
        #endif

        // Step C: fallback to the top Vision label
        return topLabel
    }
}
