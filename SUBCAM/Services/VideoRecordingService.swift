import AVFoundation
import Photos
import UIKit

final class VideoRecordingService: NSObject, ObservableObject, @unchecked Sendable {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

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
    var subtitleMode: SubtitleMode = .speech
    var cinemaScope = false
    var cinematicMode = false
    var monochromeMode = false
    var letterboxColor: LetterboxColor = .black
    var subtitlePosition: SubtitlePosition = .bottom

    // Danmaku scroll state
    private var danmakuOffsetX: CGFloat = 0
    private var danmakuLastText: String = ""
    private var danmakuStartTime: CFTimeInterval = 0
    private var danmakuAnimating: Bool = false
    private static let danmakuDuration: CFTimeInterval = 3.2

    private var _isRecordingInternal = false
    private var isWritingStarted = false
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0

    private var isRecordingInternal: Bool {
        get { _isRecordingInternal }
        set { _isRecordingInternal = newValue }
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
                        DispatchQueue.main.async { self.isRecording = false }
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

        guard writer.status == .writing,
              let videoInput,
              videoInput.isReadyForMoreMediaData else { return }

        // Get current subtitle text based on mode
        let subtitleText: String
        if subtitleMode == .aiVision {
            subtitleText = aiVisionService?.currentText ?? ""
        } else {
            subtitleText = speechService?.currentText ?? ""
        }

        // Update danmaku offset
        var currentDanmakuOffset: CGFloat = 0
        if subtitlePosition == .danmaku && !subtitleText.isEmpty {
            let frameWidth = CGFloat(videoWidth)
            if danmakuAnimating {
                // Animation in progress — just update text, don't restart scroll
                danmakuLastText = subtitleText
            } else {
                // New sentence — start fresh animation
                danmakuLastText = subtitleText
                danmakuStartTime = CACurrentMediaTime()
                danmakuAnimating = true
            }
            let elapsed = CACurrentMediaTime() - danmakuStartTime
            let progress = CGFloat(elapsed / Self.danmakuDuration)
            if progress >= 1.0 {
                danmakuAnimating = false
            }
            // Match preview: start at right edge (frameWidth/2 offset from center),
            // end past left edge (-frameWidth offset from center)
            // In renderer, x is direct position, so:
            // start = frameWidth, end = -frameWidth/2
            currentDanmakuOffset = frameWidth * (1.0 - progress * 1.5)
        } else if subtitlePosition == .danmaku && subtitleText.isEmpty {
            danmakuAnimating = false
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
            subtitlePosition: subtitlePosition,
            danmakuOffsetX: currentDanmakuOffset
        ) {
            pixelBufferAdaptor?.append(compositedBuffer, withPresentationTime: timestamp)
        }
    }

    func appendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.sync {
            guard isRecordingInternal, isWritingStarted,
                  let writer = assetWriter, writer.status == .writing,
                  let audioInput, audioInput.isReadyForMoreMediaData else { return }

            audioInput.append(sampleBuffer)
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
