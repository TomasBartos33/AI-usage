import AppKit
import SwiftUI

/// Content of the menu bar window: detailed state of every provider plus actions.
struct UsagePanel: View {
    let store: UsageStore
    @Environment(\.openSettings) private var openSettings
    /// Kept for the lifetime of the reusable menu window. Start expanded so
    /// opening the menu always shows every provider until the user collapses it.
    @State private var collapsedProviders: Set<ProviderID> = []

    var body: some View {
        let ids = store.orderedProviderIDs.filter { store.provider($0) != nil }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                if index > 0 { Divider().padding(.vertical, 8) }
                ProviderSection(
                    id: id,
                    snapshot: store.snapshots[id],
                    capabilities: store.capabilities(of: id),
                    isRefreshing: store.refreshing.contains(id),
                    now: store.now,
                    staleAfter: store.preferences.staleAfter,
                    isExpanded: Binding(
                        get: { !collapsedProviders.contains(id) },
                        set: { expanded in
                            if expanded {
                                collapsedProviders.remove(id)
                            } else {
                                collapsedProviders.insert(id)
                            }
                        }
                    )
                )
            }
            if store.preferences.demoMode {
                Text("Demo data — not real usage")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }
            Divider().padding(.vertical, 8)
            actions
        }
        .padding(14)
        .frame(width: 300)
        // The menu bar window is reused; refresh each time it is shown.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow, !window.styleMask.contains(.titled) else { return }
            store.menuOpened()
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuActionButton(title: "Refresh", systemImage: "arrow.clockwise", shortcut: "r") {
                store.refreshAll(trigger: .manual)
            }
            .disabled(!store.refreshing.isEmpty)
            ForEach(store.orderedProviderIDs, id: \.self) { id in
                if let appURL = AppLauncher.applicationURL(for: id) {
                    MenuActionButton(title: "Open \(ProviderBranding.of(id).shortName)", systemImage: "arrow.up.forward.app") {
                        AppLauncher.open(appURL)
                    }
                }
            }
            MenuActionButton(title: "Settings…", systemImage: "gearshape", shortcut: ",") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            MenuActionButton(title: "Quit AI-usage", systemImage: "power", shortcut: "q") {
                NSApp.terminate(nil)
            }
        }
    }
}

enum AppLauncher {
    static func applicationURL(for id: ProviderID) -> URL? {
        for bundleID in ProviderBranding.of(id).appBundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return url }
        }
        return nil
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// A full-width, menu-like button with hover highlight.
struct MenuActionButton: View {
    let title: String
    let systemImage: String
    var shortcut: KeyEquivalent?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if let shortcut {
                    Text("⌘\(String(shortcut.character).uppercased())")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.primary.opacity(0.1) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .modifier(OptionalShortcut(key: shortcut))
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}

/// Detailed state of one provider. Only shows fields that actually have values.
struct ProviderSection: View {
    let id: ProviderID
    let snapshot: UsageSnapshot?
    let capabilities: ProviderCapabilities
    let isRefreshing: Bool
    let now: Date
    let staleAfter: TimeInterval
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded {
                if let snapshot {
                    if !snapshot.windows.isEmpty {
                        ForEach(snapshot.windows) { window in
                            WindowRow(window: window, now: now, stale: snapshot.freshness(at: now, staleAfter: staleAfter) == .stale)
                        }
                    } else if snapshot.status == .ok, capabilities.supportsRateLimits {
                        Text("No rate-limit data yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    details(snapshot)
                    if let note = snapshot.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    footer(snapshot)
                } else {
                    Text(isRefreshing ? "Loading…" : "No data")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ProviderBranding.of(id).displayName)
                .font(.headline)
            if let plan = snapshot?.account?.plan {
                Text(plan)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            Spacer()
            if isRefreshing {
                ProgressView().controlSize(.mini)
            } else if let status = snapshot?.status, status.isProblem {
                Label(status.summary, systemImage: statusSymbol(status))
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let appURL = AppLauncher.applicationURL(for: id) {
                Button {
                    AppLauncher.open(appURL)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Open \(ProviderBranding.of(id).shortName)")
                .accessibilityLabel("Open \(ProviderBranding.of(id).shortName)")
            }
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(ProviderBranding.of(id).displayName) details" : "Show \(ProviderBranding.of(id).displayName) details")
            .accessibilityLabel(isExpanded ? "Collapse \(ProviderBranding.of(id).displayName) details" : "Show \(ProviderBranding.of(id).displayName) details")
        }
    }

    @ViewBuilder
    private func details(_ snapshot: UsageSnapshot) -> some View {
        let session = snapshot.session
        let rows: [(String, String)] = [
            ("Model", session?.model),
            ("Context", session.flatMap(contextText)),
            ("Tokens", session.flatMap(tokenText)),
            ("Cost", session?.costUSD.map(UsageFormatting.usd)),
            ("Project", session?.workingDirectory.map(UsageFormatting.projectName)),
            ("Last activity", session?.lastActivity.map { UsageFormatting.relativePast($0, now: now) }),
            ("Credits", snapshot.account?.creditsBalance),
        ].compactMap { label, value in value.map { (label, $0) } }

        if !rows.isEmpty {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                ForEach(rows, id: \.0) { label, value in
                    GridRow {
                        Text(label).foregroundStyle(.secondary)
                        Text(value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
            .font(.callout)
        }
    }

    private func footer(_ snapshot: UsageSnapshot) -> some View {
        let freshness = snapshot.freshness(at: now, staleAfter: staleAfter)
        var parts: [String] = []
        if let observed = snapshot.rateLimitsObservedAt {
            parts.append("Updated \(UsageFormatting.relativePast(observed, now: now))")
        } else {
            parts.append("Checked \(UsageFormatting.relativePast(snapshot.refreshedAt, now: now))")
        }
        if let source = snapshot.rateLimitsSource ?? snapshot.sessionSource {
            parts.append(source.displayName)
        }
        return HStack(spacing: 4) {
            if freshness == .stale {
                Image(systemName: "clock.badge.exclamationmark")
                    .help("This value was recorded earlier and may be out of date.")
            }
            Text(parts.joined(separator: " · "))
        }
        .font(.caption)
        .foregroundStyle(freshness == .stale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
    }

    private func contextText(_ session: SessionInfo) -> String? {
        if let percent = session.contextUsedPercent {
            if let window = session.contextWindowTokens {
                return "\(UsageFormatting.percent(percent)) of \(UsageFormatting.tokens(window))"
            }
            return UsageFormatting.percent(percent)
        }
        if let tokens = session.contextTokens {
            return "\(UsageFormatting.tokens(tokens)) tokens"
        }
        return nil
    }

    private func tokenText(_ session: SessionInfo) -> String? {
        guard session.inputTokens != nil || session.outputTokens != nil else { return nil }
        let input = session.inputTokens.map { "\(UsageFormatting.tokens($0)) in" }
        let output = session.outputTokens.map { "\(UsageFormatting.tokens($0)) out" }
        return [input, output].compactMap { $0 }.joined(separator: " · ")
    }

    private func statusSymbol(_ status: ProviderStatus) -> String {
        switch status {
        case .ok: return "checkmark.circle"
        case .notInstalled: return "xmark.circle"
        case .notAuthenticated: return "person.crop.circle.badge.xmark"
        case .noData: return "tray"
        case .error: return "exclamationmark.triangle"
        }
    }
}

struct WindowRow: View {
    let window: UsageWindow
    let now: Date
    let stale: Bool

    var body: some View {
        let reset = window.hasReset(at: now)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.name)
                    .font(.callout.weight(.medium))
                Spacer()
                if reset {
                    Text("window reset")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let used = window.usedPercent {
                    Text("\(UsageFormatting.percent(used)) used")
                        .font(.callout.monospacedDigit())
                }
            }
            if let used = window.usedPercent, !reset {
                UsageBar(fraction: min(max(used, 0), 100) / 100, tint: tint(for: used))
                    .opacity(stale ? 0.5 : 1)
            }
            if let resetsAt = window.resetsAt {
                Text(reset ? "Awaiting new data" : UsageFormatting.resetDescription(resetsAt, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tint(for used: Double) -> Color {
        switch used {
        case 90...: return .red
        case 75..<90: return .orange
        default: return .accentColor
        }
    }
}

/// Thin capsule progress bar (renders identically on screen and in exported snapshots).
struct UsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tint)
                    .frame(width: max(fraction > 0 ? 4 : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
