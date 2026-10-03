import AppKit
import SwiftUI

@main
struct AIUsageApp: App {
    @State private var preferences: Preferences
    @State private var store: UsageStore

    init() {
        let preferences = Preferences()
        let store = UsageStore(preferences: preferences)
        _preferences = State(initialValue: preferences)
        _store = State(initialValue: store)
        // The unit test bundle is hosted by the app; don't start watchers or subprocesses there.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            store.start()
            #if DEBUG
            if let directory = SnapshotExporter.requestedDirectory {
                SnapshotExporter.exportWhenReady(store: store, to: directory)
            }
            #endif
        }
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store, preferences: preferences)
        }
    }
}
