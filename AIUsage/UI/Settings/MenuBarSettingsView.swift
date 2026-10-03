import SwiftUI

struct MenuBarSettingsView: View {
    let store: UsageStore
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                ForEach(Array(preferences.providerOrder.enumerated()), id: \.element) { index, id in
                    ProviderDisplayEditor(
                        id: id,
                        capabilities: store.capabilities(of: id),
                        settings: Binding(
                            get: { preferences.displaySettings(for: id) },
                            set: { preferences.display[id] = $0 }
                        ),
                        canMoveUp: index > 0,
                        canMoveDown: index < preferences.providerOrder.count - 1,
                        move: { preferences.move(id, by: $0) }
                    )
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Order here is the order in the menu bar and in the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Layout") {
                Picker("Separator", selection: $preferences.separator) {
                    Text("Space").tag("  ")
                    Text("Dot ·").tag("  ·  ")
                    Text("Bar |").tag("  |  ")
                }
                HStack {
                    Text("Preview")
                    Spacer()
                    MenuBarLabel(store: store)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                }
                Button("Reset to Defaults") { preferences.resetDisplaySettings() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProviderDisplayEditor: View {
    let id: ProviderID
    let capabilities: ProviderCapabilities
    @Binding var settings: ProviderDisplaySettings
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Picker("Content", selection: $settings.content) {
                ForEach(LabelContent.allCases) { Text($0.displayName).tag($0) }
            }
            if settings.content != .valueOnly {
                Picker("Icon", selection: $settings.iconStyle) {
                    ForEach(IconStyle.allCases) { style in
                        Text(iconTitle(style)).tag(style)
                    }
                }
            }
            if settings.content != .iconOnly {
                if capabilities.supportsRateLimits {
                    Picker("Primary value", selection: $settings.primaryWindow) {
                        ForEach(availableWindows) { Text($0.displayName).tag($0) }
                    }
                    Picker("Secondary value", selection: $settings.secondaryWindow) {
                        Text("None").tag(WindowSelector?.none)
                        ForEach(availableWindows) { Text($0.displayName).tag(WindowSelector?.some($0)) }
                    }
                    Picker("Show", selection: $settings.valueMode) {
                        ForEach(ValueMode.allCases) { Text("\($0.displayName) %").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Window label (5h, W)", isOn: $settings.showWindowLabel)
                    if capabilities.supports(.resetTime) {
                        Toggle("Reset countdown", isOn: $settings.showResetCountdown)
                    }
                } else {
                    Text("This provider does not report rate limits.")
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack {
                Toggle(isOn: $settings.showInMenuBar) {
                    Text(ProviderBranding.of(id).displayName)
                }
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!canMoveUp)
                    .help("Move left")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!canMoveDown)
                    .help("Move right")
            }
            .buttonStyle(.borderless)
        }
    }

    private var availableWindows: [WindowSelector] {
        WindowSelector.allCases.filter { selector in
            switch selector {
            case .session: return capabilities.supports(.sessionWindow)
            case .weekly: return capabilities.supports(.weeklyWindow)
            case .mostConstrained: return true
            }
        }
    }

    private func iconTitle(_ style: IconStyle) -> String {
        let branding = ProviderBranding.of(id)
        switch style {
        case .glyph: return "Glyph \(branding.glyph)"
        case .name: return "Name “\(branding.shortName)”"
        default: return style.displayName
        }
    }
}
