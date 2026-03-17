import CoreGraphics
import CoreVideo
import CoreImage
import UIKit

struct SubtitleRenderer {

    // CinemaScope aspect ratio 2.39:1
    static let cinemaScopeRatio: CGFloat = 2.39

    // Shared CIContext for cinematic filter processing (reused for performance)
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func render(text: String, onto sourceBuffer: CVPixelBuffer, outputPool: CVPixelBufferPool?, cinemaScope: Bool = false, cinematicMode: Bool = false, monochromeMode: Bool = false, subtitleScale: CGFloat = 1.0, letterboxColor: LetterboxColor = .black, subtitlePosition: SubtitlePosition = .bottom, danmakuOffsetX: CGFloat = 0) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)

        // Create output pixel buffer
        var outputBuffer: CVPixelBuffer?
        if let pool = outputPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
            guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }
            outputBuffer = output
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &outputBuffer)
            guard outputBuffer != nil else { return nil }
        }

        guard let output = outputBuffer else { return nil }

        // Apply color grading (cinematic and monochrome can be combined)
        if cinematicMode || monochromeMode {
            applyColorGrading(source: sourceBuffer, destination: output, cinematic: cinematicMode, monochrome: monochromeMode)
        } else {
            // Simple copy
            CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
            CVPixelBufferLockBaseAddress(output, [])

            let srcData = CVPixelBufferGetBaseAddress(sourceBuffer)
            let dstData = CVPixelBufferGetBaseAddress(output)
            let srcBytesPerRow = CVPixelBufferGetBytesPerRow(sourceBuffer)
            let dstBytesPerRow = CVPixelBufferGetBytesPerRow(output)

            if srcBytesPerRow == dstBytesPerRow {
                memcpy(dstData, srcData, srcBytesPerRow * height)
            } else {
                for row in 0..<height {
                    let srcRow = srcData!.advanced(by: row * srcBytesPerRow)
                    let dstRow = dstData!.advanced(by: row * dstBytesPerRow)
                    memcpy(dstRow, srcRow, min(srcBytesPerRow, dstBytesPerRow))
                }
            }

            CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
        }

        // Draw text overlay
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        let dstData = CVPixelBufferGetBaseAddress(output)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(output)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: dstData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: dstBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return output }

        context.textMatrix = .identity
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let cgWidth = CGFloat(width)
        let cgHeight = CGFloat(height)

        if cinemaScope {
            renderCinemaScope(context: context, text: text, width: cgWidth, height: cgHeight, subtitleScale: subtitleScale, letterboxColor: letterboxColor, subtitlePosition: subtitlePosition, danmakuOffsetX: danmakuOffsetX)
        } else {
            renderStandard(context: context, text: text, width: cgWidth, height: cgHeight, subtitleScale: subtitleScale, subtitlePosition: subtitlePosition, danmakuOffsetX: danmakuOffsetX)
        }

        return output
    }

    // MARK: - Color grading (cinematic and monochrome can be combined)

    private static func applyColorGrading(source: CVPixelBuffer, destination: CVPixelBuffer, cinematic: Bool, monochrome: Bool) {
        var image = CIImage(cvPixelBuffer: source)
        let bounds = image.extent

        // Step 1: Cinematic grade (contrast + warm tone)
        if cinematic {
            if let colorControls = CIFilter(name: "CIColorControls") {
                colorControls.setValue(image, forKey: kCIInputImageKey)
                colorControls.setValue(1.15, forKey: kCIInputContrastKey)
                colorControls.setValue(monochrome ? 0.0 : 1.02, forKey: kCIInputSaturationKey)
                colorControls.setValue(0.0, forKey: kCIInputBrightnessKey)
                if let output = colorControls.outputImage {
                    image = output
                }
            }

            // Warm temperature shift (still applies in mono for tonal warmth)
            if let tempFilter = CIFilter(name: "CITemperatureAndTint") {
                tempFilter.setValue(image, forKey: kCIInputImageKey)
                tempFilter.setValue(CIVector(x: 6800, y: 0), forKey: "inputNeutral")
                tempFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
                if let warmed = tempFilter.outputImage {
                    image = warmed
                }
            }
        }

        // Step 2: Monochrome (desaturation + contrast boost)
        if monochrome && !cinematic {
            // Standalone mono: desaturate + slight contrast
            if let colorControls = CIFilter(name: "CIColorControls") {
                colorControls.setValue(image, forKey: kCIInputImageKey)
                colorControls.setValue(0.0, forKey: kCIInputSaturationKey)
                colorControls.setValue(1.1, forKey: kCIInputContrastKey)
                colorControls.setValue(0.0, forKey: kCIInputBrightnessKey)
                if let output = colorControls.outputImage {
                    image = output
                }
            }
        }

        ciContext.render(image, to: destination, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    private static func copyPixelBuffer(from source: CVPixelBuffer, to destination: CVPixelBuffer) {
        let height = CVPixelBufferGetHeight(source)
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])

        let srcData = CVPixelBufferGetBaseAddress(source)
        let dstData = CVPixelBufferGetBaseAddress(destination)
        let srcBPR = CVPixelBufferGetBytesPerRow(source)
        let dstBPR = CVPixelBufferGetBytesPerRow(destination)

        if srcBPR == dstBPR {
            memcpy(dstData, srcData, srcBPR * height)
        } else {
            for row in 0..<height {
                memcpy(dstData!.advanced(by: row * dstBPR),
                       srcData!.advanced(by: row * srcBPR),
                       min(srcBPR, dstBPR))
            }
        }

        CVPixelBufferUnlockBaseAddress(source, .readOnly)
        CVPixelBufferUnlockBaseAddress(destination, [])
    }

    // MARK: - Standard mode (portrait, semi-transparent bar)

    // Minimum subtitle bar height in points
    private static let minBarHeight: CGFloat = 56

    private static func renderStandard(context: CGContext, text: String, width: CGFloat, height: CGFloat, subtitleScale: CGFloat = 1.0, subtitlePosition: SubtitlePosition = .bottom, danmakuOffsetX: CGFloat = 0) {
        guard !text.isEmpty else { return }

        let barHeight = max(height * 0.12 * subtitleScale, minBarHeight)
        let barPadding = width * 0.05

        let fontSize = 20.0 * subtitleScale * (width / 390.0)  // Scale relative to iPhone 14 Pro width
        let subtitleFont = SettingsService.shared.subtitleFont
        let font = subtitleFont.uiFont(size: fontSize, bold: true)

        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black
        shadow.shadowOffset = CGSize(width: 2, height: 2)
        shadow.shadowBlurRadius = 3

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = subtitlePosition == .danmaku ? .left : .center
        paragraphStyle.lineBreakMode = subtitlePosition == .danmaku ? .byClipping : .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .shadow: shadow,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)

        switch subtitlePosition {
        case .top:
            let barY: CGFloat = 0
            context.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
            context.fill(CGRect(x: 0, y: barY, width: width, height: barHeight))
            let textRect = CGRect(
                x: barPadding,
                y: barY + (barHeight - fontSize * 2.4) / 2,
                width: width - barPadding * 2,
                height: fontSize * 2.4
            )
            UIGraphicsPushContext(context)
            attributedString.draw(in: textRect)
            UIGraphicsPopContext()

        case .center:
            let barY = (height - barHeight) / 2
            context.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
            context.fill(CGRect(x: 0, y: barY, width: width, height: barHeight))
            let textRect = CGRect(
                x: barPadding,
                y: barY + (barHeight - fontSize * 2.4) / 2,
                width: width - barPadding * 2,
                height: fontSize * 2.4
            )
            UIGraphicsPushContext(context)
            attributedString.draw(in: textRect)
            UIGraphicsPopContext()

        case .bottom:
            let barY = height - barHeight
            context.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
            context.fill(CGRect(x: 0, y: barY, width: width, height: barHeight))
            let textRect = CGRect(
                x: barPadding,
                y: barY + (barHeight - fontSize * 2.4) / 2,
                width: width - barPadding * 2,
                height: fontSize * 2.4
            )
            UIGraphicsPushContext(context)
            attributedString.draw(in: textRect)
            UIGraphicsPopContext()

        case .danmaku:
            // Y position based on text hash
            let hash = abs(text.hashValue)
            let yRatio = CGFloat(hash % 5) / 6.0 + 0.15
            let yPos = height * yRatio
            let textSize = attributedString.size()
            let textRect = CGRect(
                x: danmakuOffsetX,
                y: yPos,
                width: textSize.width + 20,
                height: fontSize * 2.4
            )
            UIGraphicsPushContext(context)
            attributedString.draw(in: textRect)
            UIGraphicsPopContext()
        }
    }

    // MARK: - CinemaScope mode (landscape, letterbox bars, cinematic subtitle)

    private static func renderCinemaScope(context: CGContext, text: String, width: CGFloat, height: CGFloat, subtitleScale: CGFloat = 1.0, letterboxColor: LetterboxColor = .black, subtitlePosition: SubtitlePosition = .bottom, danmakuOffsetX: CGFloat = 0) {
        let referenceAspect: CGFloat = 16.0 / 9.0
        let referenceHeight = width / referenceAspect
        let cinemaScopeHeight = width / cinemaScopeRatio
        let barHeight = max((referenceHeight - cinemaScopeHeight) / 2, minBarHeight)

        let rgb = letterboxColor.rgbComponents
        let barUIColor = UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1.0)
        context.setFillColor(barUIColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: barHeight))
        context.fill(CGRect(x: 0, y: height - barHeight, width: width, height: barHeight))

        guard !text.isEmpty else { return }

        // Font size: fit 1 line within bar, clamp to bar height
        let maxFontSize = barHeight * 0.55
        let baseFontSize = 18.0 * subtitleScale * (width / 844.0)  // Scale relative to iPhone 14 Pro landscape width
        let fontSize = min(baseFontSize, maxFontSize)
        let subtitleFont = SettingsService.shared.subtitleFont
        let font = subtitleFont.uiFont(size: fontSize, bold: false)

        let shadow = NSShadow()
        if letterboxColor.usesDarkText {
            shadow.shadowColor = UIColor.white.withAlphaComponent(0.3)
        } else {
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
        }
        shadow.shadowOffset = CGSize(width: 1, height: 1)
        shadow.shadowBlurRadius = 4

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = subtitlePosition == .danmaku ? .left : .center
        paragraphStyle.lineBreakMode = subtitlePosition == .danmaku ? .byClipping : .byTruncatingTail

        let subtitleColor: UIColor = letterboxColor.usesDarkText
            ? UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            : UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1.0)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: subtitleColor,
            .shadow: shadow,
            .paragraphStyle: paragraphStyle,
            .kern: 1.5
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textPadding = width * 0.1
        let textHeight = min(fontSize * 1.4, barHeight * 0.85)

        switch subtitlePosition {
        case .top:
            let textRect = CGRect(
                x: textPadding,
                y: (barHeight - textHeight) / 2,
                width: width - textPadding * 2,
                height: textHeight
            )
            UIGraphicsPushContext(context)
            attributedString.draw(in: textRect)
            UIGraphicsPopContext()

        case .center:
            let textRect = CGRect(
                x: textPadding,
                y: (height - textHeight) / 2,
                width: width - textPadding * 2,
                height: textHeight
            )
            UIGraphicsPushContext(context)
            attributedString.draw(in: textRect)
            UIGraphicsPopContext()

        case .bottom:
            let bottomBarY = height - barHeight
            let textRect = CGRect(
                x: textPadding,
                y: bottomBarY + (barHeight - textHeight) / 2,
                width: width - textPadding * 2,
                height: textHeight
            )
            UIGraphicsPushContext(context)
            attributedString.draw(in: textRect)
            UIGraphicsPopContext()

        case .danmaku:
            // Scroll within the video area between bars
            let hash = abs(text.hashValue)
            let videoAreaTop = barHeight
            let videoAreaHeight = height - barHeight * 2
            let yRatio = CGFloat(hash % 5) / 6.0 + 0.15
            let yPos = videoAreaTop + videoAreaHeight * yRatio
            let textSize = attributedString.size()
            let textRect = CGRect(
                x: danmakuOffsetX,
                y: yPos,
                width: textSize.width + 20,
                height: textHeight
            )
            UIGraphicsPushContext(context)
            attributedString.draw(in: textRect)
            UIGraphicsPopContext()
        }
    }

    /// Calculate letterbox bar height ratio for preview overlay
    /// Uses 16:9 reference to ensure consistent bar size regardless of screen aspect
    static func cinemaScopeBarRatio(frameWidth: CGFloat, frameHeight: CGFloat) -> CGFloat {
        let referenceAspect: CGFloat = 16.0 / 9.0
        let referenceHeight = frameWidth / referenceAspect
        let cinemaScopeHeight = frameWidth / cinemaScopeRatio
        let barHeight = max((referenceHeight - cinemaScopeHeight) / 2, minBarHeight)
        return barHeight / frameHeight
    }
}
