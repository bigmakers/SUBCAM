import Foundation
import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// On-device subtitle translation using Apple's Translation framework (iOS 18+).
/// Recognized speech text is submitted via `submit(_:)`; the translated text is
/// published for the UI and exposed thread-safely for the recording burn-in.
final class TranslationService: ObservableObject, @unchecked Sendable {

    // Thread-safe translated text for subtitle renderer (read from video queue)
    private let textLock = NSLock()
    private var _currentText: String = ""
    var currentText: String {
        get { textLock.lock(); defer { textLock.unlock() }; return _currentText }
        set { textLock.lock(); _currentText = newValue; textLock.unlock() }
    }

    // Published text for UI display (main thread only)
    @Published var displayText: String = ""

    // Latest-wins buffer of recognized texts awaiting translation.
    // The consumer loop lives inside the SwiftUI translationTask closure so the
    // TranslationSession never escapes its valid lifetime.
    private let streamLock = NSLock()
    private var continuation: AsyncStream<String>.Continuation?

    /// Creates a fresh request stream, finishing any previous one.
    /// Buffering keeps only the newest text, so partial recognition results
    /// arriving faster than translation naturally coalesce.
    func makeRequestStream() -> AsyncStream<String> {
        streamLock.lock(); defer { streamLock.unlock() }
        continuation?.finish()
        let (stream, continuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        return stream
    }

    func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clear()
            return
        }
        streamLock.lock(); defer { streamLock.unlock() }
        continuation?.yield(trimmed)
    }

    func publish(_ translated: String) {
        currentText = translated
        DispatchQueue.main.async {
            self.displayText = translated
        }
    }

    func clear() {
        currentText = ""
        DispatchQueue.main.async {
            self.displayText = ""
        }
    }
}

/// Invisible host view that owns the translation session for the recording screen.
/// Attached as a zero-sized leaf so toggling translation on/off never disturbs
/// the identity of the surrounding view tree.
struct SpeechTranslationHost: View {
    let service: TranslationService
    let translation: SpeechTranslation
    let sourceLanguageId: String

    var body: some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            if let target = activeTargetCode {
                Color.clear
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .translationTask(
                        TranslationSession.Configuration(
                            source: Locale.Language(identifier: sourceLanguageId),
                            target: Locale.Language(identifier: target)
                        )
                    ) { session in
                        // Sequentially translate the latest recognized text.
                        // On failure (e.g. language pack not downloaded yet),
                        // fall back to showing the original text.
                        for await text in service.makeRequestStream() {
                            do {
                                let response = try await session.translate(text)
                                service.publish(response.targetText)
                            } catch {
                                service.publish(text)
                            }
                        }
                    }
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
        #else
        Color.clear.frame(width: 0, height: 0)
        #endif
    }

    /// Target language code, or nil when translation is off or the speech
    /// language already matches the target (e.g. ja-JP → Japanese).
    private var activeTargetCode: String? {
        guard let target = translation.targetLanguageCode else { return nil }
        let source = sourceLanguageId.split(separator: "-").first.map(String.init) ?? sourceLanguageId
        return source == target ? nil : target
    }
}
