import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        switch SettingsService.shared.orientationLock {
        case .portrait:
            return .portrait
        case .landscape:
            return .landscape
        case .auto:
            return .allButUpsideDown
        }
    }
}

@main
struct SUBCAMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        #if DEBUG
        // `-renderTest` launch argument: render sample captions through the burn-in
        // path and write PNGs to Documents/renderTest (used to verify truncation fixes
        // on the simulator without recording).
        if CommandLine.arguments.contains("-renderTest") {
            RenderTest.run()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

#if DEBUG
import CoreImage

enum RenderTest {
    static func run() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("renderTest")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let texts: [(String, String)] = [
            ("ja60", "窓際の机に置かれたノートパソコンの横で、白い猫が丸くなって気持ちよさそうに昼寝をしている穏やかな午後の室内の様子です"),
            ("en120", "A white cat is curled up asleep next to a laptop on a desk by the window, enjoying a quiet and peaceful afternoon indoors."),
            ("ja20", "白い猫が机の上で昼寝をしている"),
        ]
        let frames: [(String, Int, Int)] = [("portrait", 1080, 1920), ("landscape", 1920, 1080)]
        let ciContext = CIContext()

        for (frameName, w, h) in frames {
            for (textName, text) in texts {
                for scope in [false, true] {
                    for scale in [CGFloat(1.0), 1.5] {
                        for position in [SubtitlePosition.bottom, .center] {
                            guard let src = makeGrayBuffer(width: w, height: h) else { continue }
                            guard let out = SubtitleRenderer.render(
                                text: text, onto: src, outputPool: nil,
                                cinemaScope: scope, subtitleScale: scale,
                                letterboxColor: .black, subtitlePosition: position
                            ) else { continue }
                            let ci = CIImage(cvPixelBuffer: out)
                            guard let cg = ciContext.createCGImage(ci, from: ci.extent),
                                  let png = UIImage(cgImage: cg).pngData() else { continue }
                            let name = "\(frameName)_\(textName)_\(scope ? "scope" : "std")_\(position.rawValue)_x\(scale == 1.0 ? "1" : "1.5").png"
                            try? png.write(to: dir.appendingPathComponent(name))
                        }
                    }
                }
            }
        }
        print("RENDERTEST_DONE \(dir.path)")
    }

    private static func makeGrayBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                               bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
            ctx.setFillColor(UIColor(white: 0.45, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }
}
#endif
