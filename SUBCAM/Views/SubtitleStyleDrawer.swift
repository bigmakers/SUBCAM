import SwiftUI

/// Bottom drawer for subtitle styling, presented over the live camera preview.
/// Every control writes straight into `SettingsService`, so the caption behind
/// the panel updates while the user is still choosing.
struct SubtitleStyleDrawer: View {
    @ObservedObject var settings: SettingsService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            styleRow(L10n.subtitleSizeLabel) {
                segmentedControl(
                    SubtitleSize.allCases,
                    selection: settings.subtitleSize,
                    title: { $0.displayName },
                    onSelect: { settings.subtitleSize = $0 }
                )
            }

            styleRow(L10n.subtitlePositionLabel) {
                segmentedControl(
                    SubtitlePosition.allCases,
                    selection: settings.subtitlePosition,
                    title: { $0.displayName },
                    onSelect: { settings.subtitlePosition = $0 }
                )
            }

            styleRow(L10n.subtitleFontHeader) {
                fontChips
            }

            if settings.cinemaScope {
                styleRow(L10n.letterbox) {
                    letterboxColors
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.5))
        .background(.ultraThinMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
    }

    // MARK: - Rows

    private func styleRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 46, alignment: .leading)
            content()
        }
    }

    private func segmentedControl<T: Hashable>(
        _ options: [T],
        selection: T,
        title: @escaping (T) -> String,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    onSelect(option)
                } label: {
                    Text(title(option))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(isSelected ? Color.white : Color.clear)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }

    private var fontChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SubtitleFont.allCases, id: \.self) { font in
                    let isSelected = settings.subtitleFont == font
                    Button {
                        settings.subtitleFont = font
                    } label: {
                        Text("あA")
                            .font(previewFont(font))
                            .lineLimit(1)
                            .foregroundColor(isSelected ? .black : .white.opacity(0.9))
                            .frame(width: 56, height: 40)
                            .background(isSelected ? Color.white : Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var letterboxColors: some View {
        HStack(spacing: 2) {
            ForEach(LetterboxColor.allCases, id: \.self) { color in
                let rgb = color.rgbComponents
                let isSelected = settings.letterboxColor == color
                Button {
                    settings.letterboxColor = color
                } label: {
                    Circle()
                        .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.yellow : Color.white.opacity(0.35),
                                        lineWidth: isSelected ? 2.5 : 1)
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
            }
        }
    }

    // MARK: - Helpers

    /// Mirrors `SubtitleOverlayView.swiftUIFont` so each chip previews itself.
    private func previewFont(_ font: SubtitleFont) -> Font {
        switch font {
        case .system:
            return .system(size: 17, weight: .bold)
        case .rounded:
            return .system(size: 17, weight: .bold, design: .rounded)
        case .serif:
            return .system(size: 17, weight: .bold, design: .serif)
        case .hiraginoSans:
            return Font.custom("HiraginoSans-W6", size: 17)
        case .hiraginoMincho:
            return Font.custom("HiraMinProN-W6", size: 17)
        }
    }
}
