#if DEBUG
import AppKit
import SwiftUI

/// Debug helper: `AI-usage --export-snapshots <dir>` renders the menu bar title and
/// the detail panel to PNG files and quits. Used to verify rendering without
/// screen-recording permission and to produce README screenshots.
@MainActor
enum SnapshotExporter {
    static var requestedDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--export-snapshots"), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static func exportWhenReady(store: UsageStore, to directory: URL) {
        Task { @MainActor in
            // Give providers a moment to deliver their first snapshots.
            for _ in 0..<40 where store.snapshots.count < store.orderedProviderIDs.count || !store.refreshing.isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for scheme in [ColorScheme.light, .dark] {
                let suffix = scheme == .light ? "light" : "dark"
                let label = MenuBarLabel(store: store)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(scheme == .light ? Color.white : Color(white: 0.15))
                    .environment(\.colorScheme, scheme)
                write(label, to: directory.appendingPathComponent("menubar-\(suffix).png"))
                let panel = UsagePanel(store: store)
                    .background(scheme == .light ? Color(white: 0.96) : Color(white: 0.13))
                    .environment(\.colorScheme, scheme)
                write(panel, to: directory.appendingPathComponent("panel-\(suffix).png"))
            }
            let items = MenuBarFormatter.items(
                snapshots: store.snapshots,
                options: .init(order: store.preferences.providerOrder, display: store.preferences.display,
                               showUnavailableProviders: store.preferences.showUnavailableProviders,
                               staleAfter: store.preferences.staleAfter),
                now: store.now)
            print("menubar:", MenuBarRenderer.accessibilityText(for: items))
            for id in store.orderedProviderIDs {
                if let snapshot = store.snapshots[id], let data = try? JSONEncoder.iso.encode(snapshot) {
                    print("\(id):", String(decoding: data, as: UTF8.self))
                }
            }
            NSApp.terminate(nil)
        }
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
