import SwiftUI

extension View {
    /// The current theme's backdrop behind a screen, list or form.
    func themedScreen() -> some View { modifier(ThemedScreen()) }

    /// Row backgrounds for a list section: the theme's surface in grouped lists, none in plain ones.
    func themedRows(plain: Bool = false) -> some View { modifier(ThemedRows(plain: plain)) }
}

private struct ThemedScreen: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(palette.background.color.ignoresSafeArea())
    }
}

private struct ThemedRows: ViewModifier {
    let plain: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.listRowBackground(plain ? Color.clear : palette.surface.color)
    }
}

/// Cards that sink a little under the finger and spring back.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

/// A settings row icon: a white symbol on a rounded colored square, as in iOS Settings.
struct SettingsIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
