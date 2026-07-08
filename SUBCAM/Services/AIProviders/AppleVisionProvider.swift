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
        // Nothing passed the precision filter → low-confidence recognition,
        // rendered as a question ("犬かな？") instead of a statement
        let isUncertain = filtered.isEmpty
        let candidates = (filtered.isEmpty ? observations.filter { $0.confidence > 0.3 } : filtered)
            .prefix(5)
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
                            ? """
                            あなたはカメラ映像のリアルタイム字幕を生成します。画像認識で検出された英語ラベルが与えられるので、映っているものを表す自然な日本語の単語またはフレーズ（10文字以内）を1つだけ出力してください。
                            ルール:
                            - 英語ラベルの直訳ではなく、日本語として自然な言葉を選ぶ
                            - 説明・記号・句読点・引用符は付けない。字幕テキストのみを出力する
                            - 「（確信度: 低）」と付いている場合は「〜かな？」のような疑問形にする
                            例:
                            ラベル: dog, grass, outdoor, park → 芝生の犬
                            ラベル: laptop, desk, indoor, screen → ノートパソコン
                            ラベル: cat, blanket（確信度: 低） → 猫かな？
                            """
                            : """
                            You generate real-time subtitles for camera footage. Given English image recognition labels, output one short natural word or phrase (a few words) describing what is shown.
                            Rules:
                            - No explanations or quotes. Output only the subtitle text.
                            - If the input is marked "(low confidence)", phrase it as a question like "a cat?"
                            Examples:
                            Labels: dog, grass, outdoor, park → dog on the grass
                            Labels: cat, blanket (low confidence) → a cat?
                            """
                    case .sentence:
                        instructions = language == .ja
                            ? """
                            あなたはカメラ映像のリアルタイム字幕を生成します。画像認識で検出された英語ラベルが与えられるので、映っている情景を自然な日本語の1文（30文字以内）で出力してください。
                            ルール:
                            - 直訳調や翻訳調を避け、日本語として自然な文にする
                            - 「〜が写っています」「〜が検出されました」のような説明口調は使わない
                            - 説明・引用符は付けず、文末の句点も不要。字幕テキストのみを出力する
                            - 「（確信度: 低）」と付いている場合は「〜だろうか？」「〜かな？」のような疑問形の文にする
                            例:
                            ラベル: dog, grass, outdoor, park → 公園の芝生で犬がくつろいでいる
                            ラベル: coffee, cup, table, indoor → テーブルにコーヒーが置かれている
                            ラベル: cat, blanket, sofa（確信度: 低） → ソファにいるのは猫かな？
                            """
                            : """
                            You generate real-time subtitles for camera footage. Given English image recognition labels, output one concise natural sentence describing the scene.
                            Rules:
                            - No explanations or quotes. Output only the subtitle text.
                            - If the input is marked "(low confidence)", phrase it as a question like "Is that a cat on the sofa?"
                            Examples:
                            Labels: dog, grass, outdoor, park → A dog relaxing on the park grass
                            Labels: cat, blanket, sofa (low confidence) → Is that a cat on the sofa?
                            """
                    }

                    let session = LanguageModelSession(instructions: instructions)
                    let options = GenerationOptions(temperature: 0.3)
                    let confidenceMark = isUncertain ? (language == .ja ? "（確信度: 低）" : " (low confidence)") : ""
                    let response = try await session.respond(
                        to: (language == .ja ? "ラベル: \(labelsList)" : "Labels: \(labelsList)") + confidenceMark,
                        options: options
                    )
                    var text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Strip quotes/trailing punctuation the model sometimes adds (keep ？/? for questions)
                    text = text.trimmingCharacters(in: CharacterSet(charactersIn: "「」『』\"'。."))
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
        return isUncertain ? "\(topLabel)?" : topLabel
    }
}
