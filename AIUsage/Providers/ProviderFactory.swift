import Foundation

@MainActor
enum ProviderFactory {
    static func makeProviders(preferences: Preferences) -> [ProviderID: any UsageProvider] {
        var result: [ProviderID: any UsageProvider] = [:]
        for id in ProviderID.builtIn {
            result[id] = DemoProvider(id: id)
        }
        return result
    }
}
