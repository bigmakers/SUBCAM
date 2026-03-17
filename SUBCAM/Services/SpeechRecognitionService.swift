import Speech
import AVFoundation

class SpeechRecognitionService: ObservableObject {
    private var speechRecognizer: SFSpeechRecognizer?
    private let recognitionQueue = DispatchQueue(label: "com.subcam.speechRecognition.queue")
    private var currentLocaleId: String = ""
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartWorkItem: DispatchWorkItem?
    private var isRecognitionActive = false

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

    func setLanguage(_ localeId: String) {
        let needsRestart = recognitionQueue.sync { isRecognitionActive }
        if needsRestart { stopRecognition() }

        currentLocaleId = localeId
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))

        if needsRestart { startRecognition() }
    }

    func startRecognition() {
        if speechRecognizer == nil {
            let localeId = SettingsService.shared.speechLanguageId
            currentLocaleId = localeId
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        recognitionQueue.sync {
            stopRecognitionLocked()
            isRecognitionActive = true
            beginRecognitionTaskLocked(with: speechRecognizer)
        }

        DispatchQueue.main.async {
            self.isRecognizing = true
        }
    }

    private func beginRecognitionTaskLocked(with speechRecognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.currentText = text
                DispatchQueue.main.async {
                    self.displayText = text
                }

                if result.isFinal {
                    self.recognitionQueue.async {
                        self.scheduleRestartLocked(after: 0.3)
                    }
                }
            }

            if error != nil {
                self.recognitionQueue.async {
                    self.scheduleRestartLocked(after: 0.3)
                }
            }
        }

        // Auto-restart before the 60-second limit
        scheduleRestartLocked(after: 55)
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
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        restartWorkItem?.cancel()
        restartWorkItem = nil

        guard isRecognitionActive,
              let speechRecognizer,
              speechRecognizer.isAvailable else { return }
        beginRecognitionTaskLocked(with: speechRecognizer)
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
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
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
