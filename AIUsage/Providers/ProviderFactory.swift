import Foundation

@MainActor
enum ProviderFactory {
    static func makeProviders(preferences: Preferences) -> [ProviderID: any UsageProvider] {
        if preferences.demoMode {
            return Dictionary(uniqueKeysWithValues: ProviderID.builtIn.map { ($0, DemoProvider(id: $0) as any UsageProvider) })
        }
        let override = preferences.codexExecutablePath.trimmingCharacters(in: .whitespaces)
        return [
            .codex: CodexProvider(executableOverride: override.isEmpty ? nil : override),
            .claude: ClaudeProvider(watchBridge: ClaudeStatusLineBridge().isInstalled),
        ]
    }
}
