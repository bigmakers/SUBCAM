import AVFoundation
import Photos
import UIKit

final class VideoRecordingService: NSObject, ObservableObject, @unchecked Sendable {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    /// Set when a recording ends because the writer failed (disk full, media reset, ...)
    @Published var lastError: String?

    private let writerQueue = DispatchQueue(label: "com.subcam.videoRecording.writerQueue")
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var outputURL: URL?
    private var durationTimer: Timer?

    var speechService: SpeechRecognitionService?
    var aiVisionService: AIVisionService?
    var translationService: TranslationService?
    var subtitleMode: SubtitleMode = .speech
    var speechTranslationActive: Bool = false
    var cinemaScope = false
    var cinematicMode = false
    var monochromeMode = false
    var letterboxColor: LetterboxColor = .black
    var subtitlePosition: SubtitlePosition = .bottom

    private var _isRecordingInternal = false
    private var isWritingStarted = false
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0

    private var isRecordingInternal: Bool {
        get { _isRecordingInternal }
        set { _isRecordingInternal = newValue }
    }

    /// Abandons the current recording after a mid-recording writer failure
    private func failRecordingLocked(_ reason: String) {
        print("[Recording] failed: \(reason)")
        let abandonedURL = outputURL
        if let writer = assetWriter, writer.status == .writing {
            writer.cancelWriting()
        }
        resetWriterStateLocked()
        if let abandonedURL {
            try? FileManager.default.removeItem(at: abandonedURL)
        }
        DispatchQueue.main.async {
            self.durationTimer?.invalidate()
            self.durationTimer = nil
            self.isRecording = false
            self.lastError = reason
        }
    }

    private func resetWriterStateLocked() {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        startTime = nil
        outputURL = nil
        isWritingStarted = false
        videoWidth = 0
        videoHeight = 0
        isRecordingInternal = false
    }

    func startRecording() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "SUBCAM_\(Date().timeIntervalSince1970).mov"
        let url = documentsPath.appendingPathComponent(fileName)
        outputURL = url

        // Clean up existing file if any
        try? FileManager.default.removeItem(at: url)

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            writerQueue.sync {
                assetWriter = writer
                videoInput = nil
                audioInput = nil
                pixelBufferAdaptor = nil
                outputURL = url
                startTime = nil
                isWritingStarted = false
                videoWidth = 0
                videoHeight = 0
                isRecordingInternal = true
            }
        } catch {
            print("Failed to create AVAssetWriter: \(error)")
            return
        }

        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingDuration = 0
        }
    }

    func stopRecording() async -> URL? {
        DispatchQueue.main.async {
            self.durationTimer?.invalidate()
            self.durationTimer = nil
        }

        return await withCheckedContinuation { continuation in
            writerQueue.async {
                self.isRecordingInternal = false

                guard let writer = self.assetWriter else {
                    self.resetWriterStateLocked()
                    DispatchQueue.main.async { self.isRecording = false }
                    continuation.resume(returning: nil)
                    return
                }

                guard self.isWritingStarted, writer.status == .writing else {
                    let abandonedURL = self.outputURL
                    writer.cancelWriting()
                    self.resetWriterStateLocked()
                    if let abandonedURL {
                        try? FileManager.default.removeItem(at: abandonedURL)
                    }
                    DispatchQueue.main.async { self.isRecording = false }
                    continuation.resume(returning: nil)
                    return
                }

                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()

                writer.finishWriting { [weak self] in
                    guard let self else {
                        continuation.resume(returning: nil)
                        return
                    }

                    self.writerQueue.async {
                        let finishedURL = self.outputURL
                        let completed = writer.status == .completed

                        if !completed {
                            print("Writer finished with error: \(String(describing: writer.error))")
                            if let finishedURL {
                                try? FileManager.default.removeItem(at: finishedURL)
                            }
                        }

                        self.resetWriterStateLocked()
                        DispatchQueue.main.async {
                            self.isRecording = false
                            if !completed {
                                self.lastError = writer.error?.localizedDescription ?? "finishWriting failed"
                            }
                        }
                        continuation.resume(returning: completed ? finishedURL : nil)
                    }
                }
            }
        }
    }

    func appendVideoBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.sync {
            appendVideoBufferLocked(sampleBuffer)
        }
    }

    private func appendVideoBufferLocked(_ sampleBuffer: CMSampleBuffer) {
        guard isRecordingInternal, let writer = assetWriter else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Setup writer inputs on first frame to get actual dimensions
        if !isWritingStarted {
            videoWidth = CVPixelBufferGetWidth(sourceBuffer)
            videoHeight = CVPixelBufferGetHeight(sourceBuffer)

            let quality = SettingsService.shared.videoQuality
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: videoWidth,
                AVVideoHeightKey: videoHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: quality.bitRate,
                    AVVideoExpectedSourceFrameRateKey: quality.frameRate
                ]
            ]
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true

            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: videoWidth,
                kCVPixelBufferHeightKey as String: videoHeight
            ]
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: vInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )

            guard writer.canAdd(vInput) else {
                print("Failed to add video input to writer")
                let abandonedURL = outputURL
                writer.cancelWriting()
                resetWriterStateLocked()
                if let abandonedURL {
                    try? FileManager.default.removeItem(at: abandonedURL)
                }
                DispatchQueue.main.async { self.isRecording = false }
                return
            }
            writer.add(vInput)
            videoInput = vInput

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true

            guard writer.canAdd(aInput) else {
                print("Failed to add audio input to writer")
                let abandonedURL = outputURL
                writer.cancelWriting()
                resetWriterStateLocked()
                if let abandonedURL {
                    try? FileManager.default.removeItem(at: abandonedURL)
                }
                DispatchQueue.main.async { self.isRecording = false }
                return
            }
            writer.add(aInput)
            audioInput = aInput

            guard writer.startWriting() else {
                print("Failed to start writing: \(String(describing: writer.error))")
                let abandonedURL = outputURL
                writer.cancelWriting()
                resetWriterStateLocked()
                if let abandonedURL {
                    try? FileManager.default.removeItem(at: abandonedURL)
                }
                DispatchQueue.main.async { self.isRecording = false }
                return
            }
            writer.startSession(atSourceTime: timestamp)
            startTime = timestamp
            isWritingStarted = true

            // Start duration timer on main thread
            DispatchQueue.main.async {
                let startSeconds = CMTimeGetSeconds(timestamp)
                self.durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.recordingDuration = CACurrentMediaTime() - startSeconds
                }
            }

            // Skip this first frame — pool may not be ready yet
            return
        }

        if writer.status == .failed {
            failRecordingLocked(writer.error?.localizedDescription ?? "video writer failed")
            return
        }
        guard writer.status == .writing,
              let videoInput,
              videoInput.isReadyForMoreMediaData else { return }

        // Get current subtitle text based on mode
        let subtitleText: String
        if subtitleMode == .aiVision {
            subtitleText = aiVisionService?.currentText ?? ""
        } else if speechTranslationActive, let translationService {
            subtitleText = translationService.currentText
        } else {
            subtitleText = speechService?.currentText ?? ""
        }

        // Render subtitle onto frame
        let scale = SettingsService.shared.subtitleSize.scale
        if let compositedBuffer = SubtitleRenderer.render(
            text: subtitleText,
            onto: sourceBuffer,
            outputPool: pixelBufferAdaptor?.pixelBufferPool,
            cinemaScope: cinemaScope,
            cinematicMode: cinematicMode,
            monochromeMode: monochromeMode,
            subtitleScale: scale,
            letterboxColor: letterboxColor,
            subtitlePosition: subtitlePosition
        ) {
            if pixelBufferAdaptor?.append(compositedBuffer, withPresentationTime: timestamp) == false,
               writer.status == .failed {
                failRecordingLocked(writer.error?.localizedDescription ?? "video append failed")
            }
        }
    }

    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.sync {
            guard isRecordingInternal, isWritingStarted, let writer = assetWriter else { return }
            if writer.status == .failed {
                failRecordingLocked(writer.error?.localizedDescription ?? "audio writer failed")
                return
            }
            guard writer.status == .writing,
                  let audioInput, audioInput.isReadyForMoreMediaData else { return }

            if !audioInput.append(sampleBuffer), writer.status == .failed {
                failRecordingLocked(writer.error?.localizedDescription ?? "audio append failed")
            }
        }
    }

    /// Recordings are written to Documents. A crash, a force-quit or a failed Photos
    /// write can leave files behind; re-save them on launch and drop stale leftovers
    /// that still can't be saved after a week.
    static func recoverLeftoverRecordings() async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in files where url.lastPathComponent.hasPrefix("SUBCAM_") && url.pathExtension == "mov" {
            if await saveToPhotoLibrary(url: url) {
                try? FileManager.default.removeItem(at: url)
            } else if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      Date().timeIntervalSince(modified) > 7 * 24 * 3600 {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func saveToPhotoLibrary(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if let error {
                    print("Failed to save to photo library: \(error)")
                }
                continuation.resume(returning: success)
            }
        }
    }
}
