import SwiftUI

struct SubtitleOverlayView: View {
    let text: String
    let cinemaScope: Bool
    var subtitleScale: CGFloat = 1.0
    var isRecording: Bool = false
    var letterboxColor: LetterboxColor = .black
    var subtitlePosition: SubtitlePosition = .bottom
    var subtitleFont: SubtitleFont = .system

    /// Convert SubtitleFont to SwiftUI Font
    private func swiftUIFont(size: CGFloat, bold: Bool) -> Font {
        switch subtitleFont {
        case .system:
            return .system(size: size, weight: bold ? .bold : .regular)
        case .rounded:
            return .system(size: size, weight: bold ? .bold : .regular, design: .rounded)
        case .serif:
            return .system(size: size, weight: bold ? .bold : .regular, design: .serif)
        case .hiraginoSans:
            return Font.custom(bold ? "HiraginoSans-W6" : "HiraginoSans-W3", size: size)
        case .hiraginoMincho:
            return Font.custom(bold ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size)
        }
    }

    private var barSwiftUIColor: Color {
        let rgb = letterboxColor.rgbComponents
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private var subtitleForeground: Color {
        letterboxColor.usesDarkText
            ? Color(red: 0.1, green: 0.1, blue: 0.1)
            : Color(red: 1.0, green: 0.98, blue: 0.94)
    }

    private var subtitleShadowColor: Color {
        letterboxColor.usesDarkText
            ? Color.white.opacity(0.3)
            : Color.black.opacity(0.8)
    }

    var body: some View {
        if cinemaScope {
            cinemaScopeOverlay
        } else {
            standardOverlay
        }
    }

    // MARK: - Standard (portrait)

    private var standardOverlay: some View {
        GeometryReader { geo in
            ZStack {
                if !text.isEmpty {
                    standardSubtitleView
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
    }

    private var standardSubtitleView: some View {
        VStack {
            if subtitlePosition == .bottom || subtitlePosition == .center {
                Spacer()
            }

            Text(text)
                .font(swiftUIFont(size: 20 * subtitleScale, bold: true))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 3, x: 1, y: 1)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.55)
                .truncationMode(.tail)
                .padding(.horizontal, 24)
                .padding(.vertical, max(12 * subtitleScale, 8))
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.6))

            if subtitlePosition == .top || subtitlePosition == .center {
                Spacer()
            }
        }
        .padding(.top, subtitlePosition == .top ? 100 : 0)
        .padding(.bottom, subtitlePosition == .bottom ? 100 : 0)
    }

    // MARK: - CinemaScope (landscape, letterbox)

    /// Calculate bar height matching the recording renderer's proportions.
    /// Uses the camera's native 16:9 aspect + resizeAspectFill mapping
    /// so preview bars match the recorded output exactly.
    private func cinemaScopeBarHeight(viewWidth: CGFloat, viewHeight: CGFloat) -> CGFloat {
        // Camera is always 16:9. Normalize to unit size.
        let cameraW: CGFloat = 9.0 / 16.0  // portrait normalized
        let cameraH: CGFloat = 1.0

        // resizeAspectFill: pick the larger scale
        let scaleW = viewWidth / cameraW
        let scaleH = viewHeight / cameraH
        let scaleFactor = max(scaleW, scaleH)

        // Bar height in camera coordinates (same formula as SubtitleRenderer)
        let refH = cameraW / (16.0 / 9.0)
        let scopeH = cameraW / SubtitleRenderer.cinemaScopeRatio
        let barH_cam = (refH - scopeH) / 2.0

        // Convert to screen points
        let barH_screen = barH_cam * scaleFactor
        return max(barH_screen, 44)
    }

    private var cinemaScopeOverlay: some View {
        GeometryReader { geo in
            let barHeight = cinemaScopeBarHeight(viewWidth: geo.size.width, viewHeight: geo.size.height)
            let barColor = isRecording ? barSwiftUIColor : barSwiftUIColor.opacity(0.5)

            ZStack {
                // Top letterbox bar
                VStack {
                    barColor
                        .frame(height: barHeight)
                    Spacer()
                }

                // Frame guide lines (preview only)
                if !isRecording {
                    VStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                            .padding(.top, barHeight)
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                            .padding(.bottom, barHeight)
                    }
                }

                // Bottom letterbox bar
                VStack {
                    Spacer()
                    barColor
                        .frame(height: barHeight)
                }

                // Subtitle text
                if !text.isEmpty {
                    cinemaScopeSubtitleView(barHeight: barHeight, totalHeight: geo.size.height)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
        }
    }

    @ViewBuilder
    private func cinemaScopeSubtitleView(barHeight: CGFloat, totalHeight: CGFloat) -> some View {
        let inBar = subtitlePosition == .top || subtitlePosition == .bottom
        let subtitleContent = Text(text)
            .font(swiftUIFont(size: inBar ? min(18 * subtitleScale, barHeight * 0.45) : 18 * subtitleScale, bold: false))
            .foregroundColor(subtitleForeground)
            .shadow(color: subtitleShadowColor, radius: 4, x: 1, y: 1)
            .tracking(1.5)
            .multilineTextAlignment(.center)
            .lineLimit(inBar ? 2 : 3)
            .minimumScaleFactor(0.55)
            .truncationMode(.tail)
            .padding(.horizontal, 40)

        switch subtitlePosition {
        case .top:
            VStack {
                subtitleContent
                    .frame(height: barHeight)
                Spacer()
            }
        case .center:
            subtitleContent
        case .bottom:
            VStack {
                Spacer()
                subtitleContent
                    .frame(height: barHeight)
            }
        }
    }
}
