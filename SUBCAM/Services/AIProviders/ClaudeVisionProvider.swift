import Foundation

struct ClaudeVisionProvider: VisionAIProvider {
    let apiKey: String
    let model: String

    func analyze(imageData: Data, prompt: String) async throws -> String {
        let base64 = imageData.base64EncodedString()
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 300,
            // Claude Sonnet 5 / Opus 5 think by default; captions need speed,
            // not reasoning, and thinking would eat the small token budget.
            "thinking": ["type": "disabled"],
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64
                        ]
                    ],
                    [
                        "type": "text",
                        "text": prompt
                    ]
                ]
            ]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionAIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            // Response bodies stay out of the caption: whatever we throw gets burned into the video
            print("[ClaudeVisionProvider] HTTP \(httpResponse.statusCode): \(String(data: data, encoding: .utf8)?.prefix(500) ?? "")")
            throw VisionAIError.apiError("Claude API \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
            throw VisionAIError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
