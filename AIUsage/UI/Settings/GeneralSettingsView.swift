import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    let store: UsageStore
    @Bindable var preferences: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        launchAtLoginError = LaunchAtLogin.set(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker("Background refresh", selection: $preferences.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: preferences.refreshInterval) { _, _ in
                    store.rescheduleBackgroundTimer()
                }
                Toggle("Refresh when the menu opens", isOn: $preferences.refreshOnMenuOpen)
                Picker("Mark data stale after", selection: $preferences.staleAfterMinutes) {
                    ForEach([10, 30, 60, 180, 720], id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) hour\(minutes == 60 ? "" : "s")")
                            .tag(minutes)
                    }
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("Local session files are watched for changes, so usage updates while you work without polling. Refreshing never sends prompts or makes model requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Toggle("Show providers without data in the menu bar", isOn: $preferences.showUnavailableProviders)
                Toggle("Demo data (for testing the interface)", isOn: $preferences.demoMode)
                    .onChange(of: preferences.demoMode) { _, _ in
                        store.configureProviders()
                    }
            }
        }
        .formStyle(.grouped)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message, or nil on success.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Could not update login item: \(error.localizedDescription)"
        }
    }
}
