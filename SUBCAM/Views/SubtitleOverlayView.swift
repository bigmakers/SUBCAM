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

    // Danmaku animation state
    @State private var danmakuOffsetX: CGFloat = 0
    @State private var danmakuText: String = ""
    @State private var danmakuYRatio: CGFloat = 0.4
    @State private var danmakuAnimating: Bool = false

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
                if subtitlePosition == .danmaku {
                    danmakuLayer(width: geo.size.width, height: geo.size.height)
                } else if !text.isEmpty {
                    standardSubtitleView
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
        .onChange(of: text) { _, newText in
            if subtitlePosition == .danmaku {
                if newText.isEmpty {
                    danmakuAnimating = false
                } else {
                    startDanmakuAnimation(text: newText)
                }
            }
        }
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
                .lineLimit(1)
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
                if subtitlePosition == .danmaku {
                    danmakuLayer(
                        width: geo.size.width,
                        height: geo.size.height,
                        topInset: barHeight,
                        bottomInset: barHeight
                    )
                } else if !text.isEmpty {
                    cinemaScopeSubtitleView(barHeight: barHeight, totalHeight: geo.size.height)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
            .onChange(of: text) { _, newText in
                if subtitlePosition == .danmaku {
                    if newText.isEmpty {
                        danmakuAnimating = false
                    } else {
                        startDanmakuAnimation(text: newText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cinemaScopeSubtitleView(barHeight: CGFloat, totalHeight: CGFloat) -> some View {
        let subtitleContent = Text(text)
            .font(swiftUIFont(size: min(18 * subtitleScale, barHeight * 0.45), bold: false))
            .foregroundColor(subtitleForeground)
            .shadow(color: subtitleShadowColor, radius: 4, x: 1, y: 1)
            .tracking(1.5)
            .multilineTextAlignment(.center)
            .lineLimit(1)
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
        case .danmaku:
            EmptyView()
        }
    }

    // MARK: - Danmaku (barrage) animation

    private func danmakuLayer(width: CGFloat, height: CGFloat, topInset: CGFloat = 100, bottomInset: CGFloat = 100) -> some View {
        let usableHeight = height - topInset - bottomInset
        let yPosition = topInset + usableHeight * danmakuYRatio

        return Group {
            if !danmakuText.isEmpty {
                Text(danmakuText)
                    .font(swiftUIFont(size: 20 * subtitleScale, bold: true))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 3, x: 1, y: 1)
                    .fixedSize()
                    .offset(x: danmakuOffsetX)
                    .position(x: width / 2, y: yPosition)
            }
        }
    }

    private func startDanmakuAnimation(text: String) {
        if danmakuAnimating {
            // Animation already running — just update text without restarting scroll
            danmakuText = text
            return
        }

        // New sentence — start fresh animation
        let hash = abs(text.hashValue)
        danmakuYRatio = CGFloat(hash % 5) / 6.0 + 0.15

        danmakuAnimating = true
        danmakuText = text

        // Set start position without animation
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            danmakuOffsetX = UIScreen.main.bounds.width / 2
        }

        // Start scroll on next frame
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 3.2)) {
                self.danmakuOffsetX = -UIScreen.main.bounds.width
            }

            // Mark animation as done after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                self.danmakuAnimating = false
            }
        }
    }
}
