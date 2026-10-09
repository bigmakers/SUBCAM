import Speech
import AVFoundation

final class SpeechRecognitionService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private var speechRecognizer: SFSpeechRecognizer?
    private let recognitionQueue = DispatchQueue(label: "com.subcam.speechRecognition.queue")
    private var currentLocaleId: String = ""
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartWorkItem: DispatchWorkItem?
    private var isRecognitionActive = false

    // Each task gets a generation so callbacks from a task we already replaced are ignored
    private var taskGeneration = 0
    // On-device recognition needs the language's dictation assets, which are usually
    // missing for languages other than the device language. Start on-device and fall
    // back to server-based recognition the first time an on-device task fails.
    private var preferOnDevice = true
    private var consecutiveErrors = 0

    // Thread-safe current text for subtitle renderer (read from video queue)
    private let textLock = NSLock()
    private var _currentText: String = ""
    var currentText: String {
        get { textLock.lock(); defer { textLock.unlock() }; return _currentText }
        set { textLock.lock(); _currentText = newValue; textLock.unlock() }
    }

    // Published text for UI display (main thread only)
    @Published var displayText: String = ""
    @Published var isRecognizing = false
    /// Non-empty when recognition can't run for the selected language (shown as a hint)
    @Published var statusHint: String = ""

    func setLanguage(_ localeId: String) {
        let needsRestart = recognitionQueue.sync { isRecognitionActive }
        if needsRestart { stopRecognition() }

        currentLocaleId = localeId
        speechRecognizer = Self.makeRecognizer(localeId)
        speechRecognizer?.delegate = self
        recognitionQueue.sync {
            preferOnDevice = true
            consecutiveErrors = 0
        }
        if speechRecognizer == nil {
            print("[Speech] no recognizer for locale \(localeId)")
            setHint(L10n.speechLanguageUnsupported)
        } else {
            setHint("")
        }

        if needsRestart { startRecognition() }
    }

    private static func makeRecognizer(_ localeId: String) -> SFSpeechRecognizer? {
        if let r = SFSpeechRecognizer(locale: Locale(identifier: localeId)) { return r }
        // Match on language code against what this device actually supports (e.g. "zh-CN" vs "zh-Hans-CN")
        let wanted = Locale(identifier: localeId)
        let supported = SFSpeechRecognizer.supportedLocales()
        if let match = supported.first(where: {
            $0.language.languageCode == wanted.language.languageCode
                && ($0.region == wanted.region || $0.language.script == wanted.language.script)
        }) ?? supported.first(where: { $0.language.languageCode == wanted.language.languageCode }) {
            return SFSpeechRecognizer(locale: match)
        }
        return nil
    }

    func startRecognition() {
        if speechRecognizer == nil {
            setLanguage(SettingsService.shared.speechLanguageId)
        }
        guard let speechRecognizer else { return }

        recognitionQueue.sync {
            stopRecognitionLocked()
            isRecognitionActive = true
            consecutiveErrors = 0
            if speechRecognizer.isAvailable {
                beginRecognitionTaskLocked(with: speechRecognizer)
            } else {
                // availabilityDidChange starts the task once the recognizer is ready
                print("[Speech] \(currentLocaleId) not available yet, waiting")
            }
        }

        DispatchQueue.main.async {
            self.isRecognizing = true
        }
    }

    // MARK: - SFSpeechRecognizerDelegate

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        recognitionQueue.async {
            // A recognizer from a previous language can still report in; only the current one counts
            guard self.isRecognitionActive, speechRecognizer === self.speechRecognizer else { return }
            if available, self.recognitionRequest == nil {
                self.beginRecognitionTaskLocked(with: speechRecognizer)
            } else if !available {
                self.setHint(L10n.speechUnavailable)
            }
        }
    }

    private func beginRecognitionTaskLocked(with speechRecognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let onDevice = preferOnDevice && speechRecognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = onDevice

        recognitionRequest = request
        taskGeneration += 1
        let generation = taskGeneration
        var gotResult = false

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            // Everything runs on recognitionQueue so a result from a task we already
            // replaced (stop, language change, 55 s restart) can't touch the caption.
            self.recognitionQueue.async {
                guard generation == self.taskGeneration, self.isRecognitionActive else { return }

                if let result {
                    gotResult = true
                    let text = result.bestTranscription.formattedString
                    self.currentText = text
                    DispatchQueue.main.async { self.displayText = text }
                    self.consecutiveErrors = 0
                    self.setHint("")
                    if result.isFinal {
                        self.scheduleRestartLocked(after: 0.3)
                    }
                }

                guard let error else { return }
                let ns = error as NSError
                print("[Speech] \(self.currentLocaleId) onDevice=\(onDevice) error \(ns.domain) \(ns.code): \(ns.localizedDescription)")
                switch Self.classify(ns) {
                case .cancelled:
                    return
                case .noSpeech:
                    // Silence until the recognizer gave up: a normal end of utterance
                    self.scheduleRestartLocked(after: 0.3)
                case .failure:
                    if onDevice && !gotResult {
                        // Most likely no on-device model for this language: retry via server
                        self.preferOnDevice = false
                        self.scheduleRestartLocked(after: 0.1)
                    } else if gotResult {
                        self.scheduleRestartLocked(after: 0.3)
                    } else {
                        self.consecutiveErrors += 1
                        if self.consecutiveErrors >= 3 {
                            self.setHint(L10n.speechUnavailable)
                        }
                        let delay = min(0.3 * pow(2.0, Double(self.consecutiveErrors - 1)), 5.0)
                        self.scheduleRestartLocked(after: delay)
                    }
                }
            }
        }

        // Auto-restart before the 60-second limit
        scheduleRestartLocked(after: 55)
    }

    private enum SpeechErrorKind { case cancelled, noSpeech, failure }

    /// Speech errors arrive from several private domains; the codes below are the ones
    /// that are not real failures (our own cancel, or simply nobody speaking).
    private static func classify(_ error: NSError) -> SpeechErrorKind {
        switch error.code {
        case 216, 301: return .cancelled     // request cancelled (kAFAssistantErrorDomain / kLSRErrorDomain)
        case 1110: return .noSpeech          // "No speech detected"
        default: return .failure
        }
    }

    private func scheduleRestartLocked(after delay: TimeInterval) {
        restartWorkItem?.cancel()
        guard isRecognitionActive else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.restartRecognitionLocked()
        }
        restartWorkItem = workItem
        recognitionQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func restartRecognitionLocked() {
        taskGeneration += 1   // orphan callbacks from the task we are cancelling
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        restartWorkItem?.cancel()
        restartWorkItem = nil

        guard isRecognitionActive, let speechRecognizer else { return }
        if speechRecognizer.isAvailable {
            beginRecognitionTaskLocked(with: speechRecognizer)
        }
        // otherwise availabilityDidChange will resume us
    }

    func stopRecognition() {
        recognitionQueue.sync {
            isRecognitionActive = false
            stopRecognitionLocked()
        }

        currentText = ""
        DispatchQueue.main.async {
            self.isRecognizing = false
            self.displayText = ""
        }
    }

    private func stopRecognitionLocked() {
        restartWorkItem?.cancel()
        restartWorkItem = nil
        taskGeneration += 1   // orphan callbacks from the task we are cancelling
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    private func setHint(_ text: String) {
        DispatchQueue.main.async {
            if self.statusHint != text { self.statusHint = text }
        }
    }

    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        recognitionQueue.sync {
            guard isRecognitionActive,
                  let request = recognitionRequest,
                  let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }

            guard let audioFormat = AVAudioFormat(streamDescription: asbd) else { return }
            let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
            guard numSamples > 0,
                  let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat,
                                                    frameCapacity: AVAudioFrameCount(numSamples)) else { return }

            pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sampleBuffer,
                at: 0,
                frameCount: Int32(numSamples),
                into: pcmBuffer.mutableAudioBufferList
            )

            guard status == noErr else { return }
            request.append(pcmBuffer)
        }
    }
}
