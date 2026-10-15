import SwiftUI
import AppKit

/// Warm neutrals with a clay accent, in the spirit of Claude's own apps. Every color adapts to light and dark
/// appearance. Lines and fills are opaque so one-point strokes draw crisply everywhere.
enum Palette {
    static let canvasColor = dynamic(0xFAF9F5, 0x262624)
    static let canvas = Color(nsColor: canvasColor)
    static let surface = Color(nsColor: dynamic(0xFFFFFF, 0x30302E))
    static let border = Color(nsColor: dynamic(0xE3E1D8, 0x45443F))
    static let text = Color(nsColor: dynamic(0x141413, 0xFAF9F5))
    static let text2 = Color(nsColor: dynamic(0x3D3D3A, 0xC2C0B6))
    static let text3 = Color(nsColor: dynamic(0x73726C, 0x9C9A92))
    static let accent = Color(nsColor: dynamic(0xC15F3C, 0xD97757))
    /// Fills behind white text.
    static let accentFill = Color(nsColor: dynamic(0xC15F3C, 0xC96442))
    static let success = Color(nsColor: dynamic(0x3F7D53, 0x86C29A))
    static let warning = Color(nsColor: dynamic(0xA8641A, 0xE5A55A))

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let lightColor = color(light), darkColor = color(dark)
        return NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor }
    }
}

extension Font {
    /// Headings, set in the system serif (New York).
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
    /// Everything else.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

/// The app's mark, drawn to match the generated app icon.
struct BrandMark: View {
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.85, green: 0.47, blue: 0.34), Color(red: 0.72, green: 0.35, blue: 0.22)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "arrow.left.arrow.right").font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color(red: 0.98, green: 0.976, blue: 0.96))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Palette.border).frame(height: 1) }
}

// MARK: Buttons

/// The one next step: clay fill, white text. Pair it with `.keyboardShortcut(.defaultAction)`.
struct ClayButtonStyle: ButtonStyle {
    var minWidth: CGFloat = 0
    func makeBody(configuration: Configuration) -> some View { ClayButton(configuration: configuration, minWidth: minWidth) }
    private struct ClayButton: View {
        let configuration: ButtonStyleConfiguration
        let minWidth: CGFloat
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            configuration.label
                .font(.ui(13, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 16).frame(minWidth: minWidth).frame(height: 34)
                .background(shape.fill(Palette.accentFill))
                .overlay(shape.fill(Color.black.opacity(configuration.isPressed ? 0.18 : 0)))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(shape)
        }
    }
}

/// A white button with a soft border.
struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 30
    func makeBody(configuration: Configuration) -> some View { OutlineButton(configuration: configuration, height: height) }
    private struct OutlineButton: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            configuration.label
                .font(.ui(12.5, weight: .medium)).foregroundStyle(Palette.text)
                .padding(.horizontal, 12).frame(height: height)
                .background(shape.fill(hovering || configuration.isPressed ? Palette.canvas : Palette.surface))
                .overlay(shape.strokeBorder(Palette.border))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(shape)
                .onHover { hovering = $0 && enabled }
        }
    }
}

/// An optional action shown as plain text that darkens on hover.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { LinkButton(configuration: configuration) }
    private struct LinkButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.ui(12.5, weight: .medium))
                .foregroundStyle(hovering || configuration.isPressed ? Palette.text : Palette.text3)
                .padding(.horizontal, 6).frame(height: 26)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 && enabled }
        }
    }
}
