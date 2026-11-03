import SwiftUI

/// Mihon's Appearance settings: theme mode, app theme with previews, pure black.
struct AppearanceView: View {
    @AppStorage(Pref.theme.name) private var theme = AppTheme.standard
    @AppStorage(Pref.themeMode.name) private var mode = ThemeMode.system
    @AppStorage(Pref.pureBlack.name) private var pureBlack = false

    var body: some View {
        List {
            Section("Theme mode") {
                Picker("Theme mode", selection: $mode) {
                    ForEach(ThemeMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .themedRows()
            Section("App theme") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(AppTheme.allCases) { option in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) { theme = option }
                            } label: {
                                ThemePreviewCard(theme: option, pureBlack: pureBlack, selected: option == theme)
                            }
                            .buttonStyle(PressableCardStyle())
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .themedRows()
            Section {
                Toggle("Pure black dark mode", isOn: $pureBlack)
            } footer: {
                Text("A black background in dark mode. Saves battery on OLED screens.")
            }
            .themedRows()
        }
        .navigationTitle("Appearance")
        .themedScreen()
    }
}

/// A tiny mock of the app in one theme, like Mihon's theme picker.
private struct ThemePreviewCard: View {
    let theme: AppTheme
    let pureBlack: Bool
    let selected: Bool

    var body: some View {
        let palette = theme.palette(pureBlack: pureBlack)
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(palette.onSurface.color.opacity(0.85)).frame(width: 46, height: 7)
                RoundedRectangle(cornerRadius: 6)
                    .fill(palette.surface.color)
                    .frame(height: 54)
                    .overlay(alignment: .bottomTrailing) {
                        Capsule().fill(palette.primary.color).frame(width: 22, height: 10).padding(6)
                    }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(palette.container.color)
                    RoundedRectangle(cornerRadius: 4).fill(palette.surface.color)
                }
                .frame(height: 30)
                Spacer(minLength: 0)
                HStack {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index == 0 ? palette.primary.color : palette.onSurfaceVariant.color.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 6)
                .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(8)
            .frame(width: 104, height: 168)
            .background(palette.background.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? palette.primary.color : Color.secondary.opacity(0.25), lineWidth: selected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(palette.onPrimary.color, palette.primary.color)
                        .padding(6)
                }
            }
            Text(theme.title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
