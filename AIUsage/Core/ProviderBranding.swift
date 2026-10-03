import Foundation

/// Static presentation metadata for a provider. Official logos are deliberately
/// not bundled; `logoAssetName` is the hook for adding licensed assets later.
struct ProviderBranding {
    let displayName: String
    let shortName: String
    let glyph: String
    let symbolName: String
    let logoAssetName: String?
    /// Desktop apps that "Open …" in the menu may launch, in preference order.
    var appBundleIdentifiers: [String] = []
    /// Monochrome template images shipped inside the provider's own desktop app
    /// (bundle ID, resource name). Loaded at runtime, never redistributed.
    var logoTemplates: [(bundleID: String, resource: String)] = []

    static func of(_ id: ProviderID) -> ProviderBranding {
        switch id {
        case .codex:
            return ProviderBranding(displayName: "Codex", shortName: "Codex", glyph: "✦",
                                    symbolName: "chevron.left.forwardslash.chevron.right", logoAssetName: nil,
                                    appBundleIdentifiers: ["com.openai.codex"],
                                    logoTemplates: [("com.openai.codex", "chatgptTemplate")])
        case .claude:
            return ProviderBranding(displayName: "Claude Code", shortName: "Claude", glyph: "◈",
                                    symbolName: "asterisk", logoAssetName: nil,
                                    appBundleIdentifiers: ["com.anthropic.claudefordesktop"],
                                    logoTemplates: [("com.anthropic.claudefordesktop", "TrayIconTemplate")])
        default:
            return ProviderBranding(displayName: id.rawValue.capitalized, shortName: id.rawValue.capitalized,
                                    glyph: "●", symbolName: "circle.dotted", logoAssetName: nil)
        }
    }
}
