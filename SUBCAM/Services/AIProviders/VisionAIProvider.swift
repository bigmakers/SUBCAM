import Foundation

protocol VisionAIProvider {
    func analyze(imageData: Data, prompt: String) async throws -> String
}

enum VisionAIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "APIキーが未設定です"
        case .invalidResponse: return "無効なレスポンス"
        case .apiError(let msg): return msg
        case .networkError(let err): return err.localizedDescription
        }
    }
}
