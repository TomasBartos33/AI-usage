import SwiftUI

struct SettingsView: View {
    private enum Section: Hashable {
        case general
        case menuBar
        case providers
    }

    let store: UsageStore
    @Bindable var preferences: Preferences
    @State private var selection: Section? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag(Section.general)
                Label("Menu Bar", systemImage: "menubar.rectangle")
                    .tag(Section.menuBar)
                Label("Providers", systemImage: "square.stack.3d.up")
                    .tag(Section.providers)
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .frame(minWidth: 170, idealWidth: 190)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        // Forms scroll within this bounded window instead of forcing its height
        // to match the longest settings pane.
        .frame(width: 760, height: 540)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            GeneralSettingsView(store: store, preferences: preferences)
                .navigationTitle("General")
        case .menuBar:
            MenuBarSettingsView(store: store, preferences: preferences)
                .navigationTitle("Menu Bar")
        case .providers:
            ProvidersSettingsView(store: store, preferences: preferences)
                .navigationTitle("Providers")
        }
    }
}
