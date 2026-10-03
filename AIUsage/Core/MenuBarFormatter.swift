import Foundation

/// One provider's portion of the menu bar title.
struct MenuBarItem: Equatable, Sendable {
    enum Icon: Equatable, Sendable {
        case symbol(String)
        case text(String)
    }

    var provider: ProviderID
    var icon: Icon?
    var text: String?
    /// Stale or unavailable data is rendered dimmed, never as if it were live.
    var dimmed: Bool
}

/// Turns normalized snapshots + display settings into menu bar items.
/// Pure and deterministic so it can be unit tested.
enum MenuBarFormatter {
    static let placeholder = "–"

    struct Options: Sendable {
        var order: [ProviderID]
        var display: [ProviderID: ProviderDisplaySettings]
        var showUnavailableProviders: Bool
        var staleAfter: TimeInterval
    }

    static func items(snapshots: [ProviderID: UsageSnapshot], options: Options, now: Date) -> [MenuBarItem] {
        options.order.compactMap { id in
            let settings = options.display[id] ?? ProviderDisplaySettings()
            guard settings.showInMenuBar else { return nil }
            return item(for: id, snapshot: snapshots[id], settings: settings, options: options, now: now)
        }
    }

    static func item(for id: ProviderID, snapshot: UsageSnapshot?, settings: ProviderDisplaySettings,
                     options: Options, now: Date) -> MenuBarItem? {
        let branding = ProviderBranding.of(id)
        let hasWindows = !(snapshot?.windows.isEmpty ?? true)
        let unavailable = snapshot == nil || (snapshot!.status.isProblem && !hasWindows)
        if unavailable && !options.showUnavailableProviders { return nil }

        let stale = snapshot?.freshness(at: now, staleAfter: options.staleAfter) == .stale
        var icon = self.icon(style: settings.iconStyle, branding: branding)
        var text: String?

        if settings.content != .iconOnly {
            text = unavailable ? placeholder : valueText(snapshot: snapshot!, settings: settings, now: now)
        }
        if settings.content == .valueOnly {
            icon = nil
        }
        // Never render an empty item.
        if icon == nil && (text?.isEmpty ?? true) {
            text = branding.shortName
        }
        return MenuBarItem(provider: id, icon: icon, text: text, dimmed: unavailable || stale)
    }

    static func icon(style: IconStyle, branding: ProviderBranding) -> MenuBarItem.Icon? {
        switch style {
        case .sparkle: return .symbol("sparkle")
        case .symbol: return .symbol(branding.symbolName)
        case .glyph: return .text(branding.glyph)
        case .name: return .text(branding.shortName)
        case .none: return nil
        }
    }

    static func valueText(snapshot: UsageSnapshot, settings: ProviderDisplaySettings, now: Date) -> String {
        var selectors = [settings.primaryWindow]
        if let secondary = settings.secondaryWindow, secondary != settings.primaryWindow {
            selectors.append(secondary)
        }
        var seen = Set<String>()
        let parts: [String] = selectors.compactMap { selector in
            guard let window = selector.resolve(in: snapshot, now: now) else { return nil }
            guard seen.insert(window.id).inserted else { return nil }
            return windowText(window, settings: settings, now: now)
        }
        return parts.isEmpty ? placeholder : parts.joined(separator: " · ")
    }

    static func windowText(_ window: UsageWindow, settings: ProviderDisplaySettings, now: Date) -> String {
        var pieces: [String] = []
        if settings.showWindowLabel { pieces.append(window.shortName) }

        if window.hasReset(at: now) {
            // The recorded percentage belongs to a window that has ended.
            pieces.append(placeholder)
            return pieces.joined(separator: " ")
        }

        let value: Double? = settings.valueMode == .used ? window.usedPercent : window.remainingPercent
        if let value {
            pieces.append(settings.showPercentSign ? UsageFormatting.percent(value) : "\(Int(value.rounded()))")
        } else if !(settings.showResetCountdown && window.resetsAt != nil) {
            pieces.append(placeholder)
        }
        if settings.showResetCountdown, let resetsAt = window.resetsAt {
            pieces.append(UsageFormatting.compactCountdown(to: resetsAt, from: now))
        }
        return pieces.joined(separator: " ")
    }
}
