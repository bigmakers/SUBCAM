import Foundation

struct LocalLLMVisionProvider: VisionAIProvider {
    let endpoint: String

    func analyze(imageData: Data, prompt: String) async throws -> String {
        let base64 = imageData.base64EncodedString()
        guard let url = URL(string: endpoint) else {
            throw VisionAIError.apiError("無効なエンドポイントURL")
        }

        // OpenAI-compatible API format (works with Ollama, etc.)
        let body: [String: Any] = [
            "model": "llava",
            "max_tokens": 100,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": prompt
                    ],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(base64)"
                        ]
                    ]
                ]
            ]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionAIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VisionAIError.apiError("ローカルLLM \(httpResponse.statusCode): \(errorMsg)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw VisionAIError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
