import SwiftUI

struct SettingsView: View {
    let store: UsageStore
    @Bindable var preferences: Preferences

    var body: some View {
        TabView {
            GeneralSettingsView(store: store, preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            MenuBarSettingsView(store: store, preferences: preferences)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            ProvidersSettingsView(store: store, preferences: preferences)
                .tabItem { Label("Providers", systemImage: "square.stack.3d.up") }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
