import SwiftUI

/// The game's button look: a beveled gunmetal plate that sits on a darker lip and presses down into it.
/// Primary plates are filled with the accent color; secondary ones carry it as a stripe on the left.
struct PlateButtonStyle: ButtonStyle {
    enum Prominence { case primary, secondary }

    var tint: Color = .orange
    var prominence = Prominence.secondary
    var size = PlateLabel.Size.regular

    func makeBody(configuration: Configuration) -> some View {
        PlateSurface(tint: tint, prominence: prominence, size: size, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

extension ButtonStyle where Self == PlateButtonStyle {
    static func plate(_ tint: Color = .orange, _ prominence: PlateButtonStyle.Prominence = .secondary, size: PlateLabel.Size = .regular) -> PlateButtonStyle {
        PlateButtonStyle(tint: tint, prominence: prominence, size: size)
    }
}

/// Text and an optional icon in the plate's lettering: uppercase, wide and spaced.
struct PlateLabel: View {
    enum Size { case small, regular, large }

    let title: String
    var systemImage: String?
    var size = Size.regular

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: fontSize * 1.05, weight: .bold))
            }
            Text(title.uppercased())
                .font(.system(size: fontSize, weight: .heavy).width(.expanded))
                .tracking(fontSize * 0.08)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var fontSize: Double {
        switch size {
        case .small: 11
        case .regular: 13
        case .large: 17
        }
    }
}

/// The plate itself, shared by buttons and menus.
struct PlateSurface<Content: View>: View {
    let tint: Color
    let prominence: PlateButtonStyle.Prominence
    var size = PlateLabel.Size.regular
    var isPressed = false
    @ViewBuilder let content: () -> Content

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let lip = size == .large ? 5.0 : 3.5
        let corner = size == .large ? 14.0 : 10.0
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        content()
            .foregroundStyle(prominence == .primary ? .white : Color(white: 0.92))
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minHeight)
            .padding(.leading, prominence == .secondary ? 5 : 0)
            .background {
                ZStack(alignment: .leading) {
                    shape.fill(face)
                    if prominence == .secondary {
                        tint.frame(width: 5)
                    }
                    shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            }
            .shadow(color: .black.opacity(0.35), radius: 0, y: 0)
            .offset(y: isPressed ? lip - 1 : 0)
            .background(alignment: .bottom) {
                shape.fill(lipColor)
                    .offset(y: lip)
            }
            .padding(.bottom, lip)
            .shadow(color: .black.opacity(isPressed ? 0.15 : 0.3), radius: isPressed ? 1 : 4, y: isPressed ? 1 : 3)
            .opacity(isEnabled ? 1 : 0.45)
            .saturation(isEnabled ? 1 : 0.3)
            .animation(.spring(duration: 0.12), value: isPressed)
            .contentShape(shape)
    }

    private var face: LinearGradient {
        switch prominence {
        case .primary:
            LinearGradient(colors: [tint.mix(with: .white, by: 0.15), tint, tint.mix(with: .black, by: 0.25)], startPoint: .top, endPoint: .bottom)
        case .secondary:
            LinearGradient(colors: [Color(white: 0.36), Color(white: 0.22), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var lipColor: Color {
        prominence == .primary ? tint.mix(with: .black, by: 0.6) : Color(white: 0.06)
    }

    private var horizontalPadding: Double {
        switch size {
        case .small: 12
        case .regular: 16
        case .large: 26
        }
    }

    private var minHeight: Double {
        switch size {
        case .small: 32
        case .regular: 40
        case .large: 54
        }
    }
}
