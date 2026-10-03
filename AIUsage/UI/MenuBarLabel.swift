import AppKit
import SwiftUI

/// The menu bar title. Rendered into a single template image so we fully
/// control layout and can dim stale values while still adapting to light/dark
/// menu bars like system items do.
struct MenuBarLabel: View {
    let store: UsageStore

    var body: some View {
        let preferences = store.preferences
        let items = MenuBarFormatter.items(
            snapshots: store.snapshots,
            options: .init(
                order: preferences.providerOrder,
                display: preferences.display,
                showUnavailableProviders: preferences.showUnavailableProviders,
                staleAfter: preferences.staleAfter
            ),
            now: store.now
        )
        Image(nsImage: MenuBarRenderer.image(for: items, separator: preferences.separator))
            .accessibilityLabel(MenuBarRenderer.accessibilityText(for: items))
    }
}

@MainActor
enum MenuBarRenderer {
    static func image(for items: [MenuBarItem], separator: String) -> NSImage {
        let content = MenuBarContent(items: items, separator: separator)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                                accessibilityDescription: "AI-usage") ?? NSImage()
        image.isTemplate = true
        return image
    }

    static func accessibilityText(for items: [MenuBarItem]) -> String {
        guard !items.isEmpty else { return "AI-usage" }
        return items.map { item in
            let name = ProviderBranding.of(item.provider).displayName
            return [name, item.text].compactMap { $0 }.joined(separator: " ")
        }.joined(separator: ", ")
    }
}

/// Plain SwiftUI layout of the menu bar items. Black on transparent: the
/// resulting image is used as a template, so only alpha matters.
private struct MenuBarContent: View {
    let items: [MenuBarItem]
    let separator: String

    var body: some View {
        HStack(spacing: 0) {
            if items.isEmpty {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 14, weight: .regular))
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Text(separator)
                    }
                    itemView(item)
                        .opacity(item.dimmed ? 0.45 : 1)
                }
            }
        }
        .font(.system(size: 13, weight: .medium).monospacedDigit())
        .foregroundStyle(.black)
        .lineLimit(1)
        .fixedSize()
        .frame(height: 18)
        .padding(.horizontal, 1)
    }

    @ViewBuilder
    private func itemView(_ item: MenuBarItem) -> some View {
        HStack(spacing: 4) {
            switch item.icon {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 12, weight: .semibold))
            case .text(let text):
                Text(text)
            case nil:
                EmptyView()
            }
            if let text = item.text {
                Text(text)
            }
        }
    }
}
