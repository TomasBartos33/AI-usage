import Foundation
import Observation

/// User preferences, persisted in `UserDefaults`. Observable so the menu bar
/// re-renders immediately when a setting changes.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let providerOrder = "providerOrder"
        static let display = "providerDisplay"
        static let refreshInterval = "refreshInterval"
        static let refreshOnMenuOpen = "refreshOnMenuOpen"
        static let showUnavailableProviders = "showUnavailableProviders"
        static let staleAfterMinutes = "staleAfterMinutes"
        static let separator = "menuBarSeparator"
        static let codexExecutablePath = "codexExecutablePath"
        static let demoMode = "demoMode"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var providerOrder: [ProviderID] {
        didSet { save(providerOrder.map(\.rawValue), Key.providerOrder) }
    }

    var display: [ProviderID: ProviderDisplaySettings] {
        didSet { saveDisplay() }
    }

    var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) }
    }

    var refreshOnMenuOpen: Bool {
        didSet { defaults.set(refreshOnMenuOpen, forKey: Key.refreshOnMenuOpen) }
    }

    /// Show providers in the menu bar even when they are not installed / have no data.
    var showUnavailableProviders: Bool {
        didSet { defaults.set(showUnavailableProviders, forKey: Key.showUnavailableProviders) }
    }

    /// Rate-limit data older than this is marked stale.
    var staleAfterMinutes: Int {
        didSet { defaults.set(staleAfterMinutes, forKey: Key.staleAfterMinutes) }
    }

    var separator: String {
        didSet { defaults.set(separator, forKey: Key.separator) }
    }

    /// Optional override for the `codex` binary location.
    var codexExecutablePath: String {
        didSet { defaults.set(codexExecutablePath, forKey: Key.codexExecutablePath) }
    }

    /// Replaces real providers with deterministic demo data (UI development, screenshots).
    var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Key.demoMode) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedOrder = (defaults.stringArray(forKey: Key.providerOrder) ?? []).map(ProviderID.init(rawValue:))
        providerOrder = Preferences.normalizedOrder(storedOrder)

        var display: [ProviderID: ProviderDisplaySettings] = [:]
        if let data = defaults.data(forKey: Key.display),
           let decoded = try? JSONDecoder().decode([String: ProviderDisplaySettings].self, from: data) {
            for (key, value) in decoded { display[ProviderID(key)] = value }
        }
        for id in ProviderID.builtIn where display[id] == nil {
            display[id] = Preferences.defaultDisplay(for: id)
        }
        self.display = display

        if defaults.object(forKey: Key.refreshInterval) != nil,
           let interval = RefreshInterval(rawValue: defaults.integer(forKey: Key.refreshInterval)) {
            refreshInterval = interval
        } else {
            refreshInterval = .fifteenMinutes
        }
        refreshOnMenuOpen = defaults.object(forKey: Key.refreshOnMenuOpen) as? Bool ?? true
        showUnavailableProviders = defaults.object(forKey: Key.showUnavailableProviders) as? Bool ?? false
        let stale = defaults.integer(forKey: Key.staleAfterMinutes)
        staleAfterMinutes = stale > 0 ? stale : 30
        separator = defaults.string(forKey: Key.separator) ?? "  "
        codexExecutablePath = defaults.string(forKey: Key.codexExecutablePath) ?? ""
        demoMode = defaults.bool(forKey: Key.demoMode)
            || ProcessInfo.processInfo.arguments.contains("--demo")
    }

    var staleAfter: TimeInterval { TimeInterval(staleAfterMinutes * 60) }

    func displaySettings(for id: ProviderID) -> ProviderDisplaySettings {
        display[id] ?? Preferences.defaultDisplay(for: id)
    }

    func update(_ id: ProviderID, _ change: (inout ProviderDisplaySettings) -> Void) {
        var settings = displaySettings(for: id)
        change(&settings)
        display[id] = settings
    }

    func move(_ id: ProviderID, by offset: Int) {
        guard let index = providerOrder.firstIndex(of: id) else { return }
        let target = index + offset
        guard providerOrder.indices.contains(target) else { return }
        providerOrder.swapAt(index, target)
    }

    func resetDisplaySettings() {
        providerOrder = ProviderID.builtIn
        display = Dictionary(uniqueKeysWithValues: ProviderID.builtIn.map { ($0, Preferences.defaultDisplay(for: $0)) })
    }

    static func defaultDisplay(for id: ProviderID) -> ProviderDisplaySettings {
        ProviderDisplaySettings()
    }

    /// Keeps the user's order, drops unknown providers and appends new ones.
    nonisolated static func normalizedOrder(_ stored: [ProviderID]) -> [ProviderID] {
        var result: [ProviderID] = []
        for id in stored where ProviderID.builtIn.contains(id) && !result.contains(id) {
            result.append(id)
        }
        for id in ProviderID.builtIn where !result.contains(id) {
            result.append(id)
        }
        return result
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func saveDisplay() {
        let encodable = Dictionary(uniqueKeysWithValues: display.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: Key.display)
        }
    }
}
