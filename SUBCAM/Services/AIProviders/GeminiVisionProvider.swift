import Foundation

struct GeminiVisionProvider: VisionAIProvider {
    let apiKey: String
    let model: String

    func analyze(imageData: Data, prompt: String) async throws -> String {
        let base64 = imageData.base64EncodedString()
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    [
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": base64
                        ]
                    ]
                ]
            ]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionAIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            // Response bodies stay out of the caption: whatever we throw gets burned into the video
            print("[GeminiVisionProvider] HTTP \(httpResponse.statusCode): \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
            throw VisionAIError.apiError("Gemini API \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw VisionAIError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
