import SwiftUI

/// Blue Lake tokens from Fujikage `packages/design-system/tokens.json` (shipping default).
enum Theme {
    static let background = Color(red: 0.008, green: 0.043, blue: 0.078)
    static let surface2 = Color(red: 0.039, green: 0.102, blue: 0.169)
    static let hairline = Color(red: 0.082, green: 0.176, blue: 0.271)
    static let hairline2 = Color(red: 0.180, green: 0.290, blue: 0.369)
    static let foreground = Color(red: 0.847, green: 0.910, blue: 0.941)
    static let foreground2 = Color(red: 0.635, green: 0.773, blue: 0.847)
    static let muted = Color(red: 0.416, green: 0.561, blue: 0.659)
    static let accent = Color(red: 0.122, green: 0.620, blue: 0.824)

    static let radiusSM: CGFloat = 8
    static let radiusMD: CGFloat = 12
    static let micro: CGFloat = 10
    static let caption: CGFloat = 12
    static let body: CGFloat = 14

    static var nsBackground: NSColor {
        NSColor(red: 0.008, green: 0.043, blue: 0.078, alpha: 1)
    }

    static var bodyMono: Font {
        .system(size: caption, weight: .semibold, design: .monospaced)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.bodyMono)
            .textCase(.uppercase)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Theme.accent)
            .foregroundStyle(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct IconToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.foreground2)
            .frame(width: 28, height: 28)
            .background(Theme.surface2)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Paints the window chrome to match Blue Lake. Traffic lights stay system.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Self.apply(to: view.window)
    }

    private static func apply(to window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.nsBackground
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
    }
}
