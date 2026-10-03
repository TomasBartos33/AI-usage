import Foundation

/// Static presentation metadata for a provider. Official logos are deliberately
/// not bundled; `logoAssetName` is the hook for adding licensed assets later.
struct ProviderBranding: Sendable {
    let displayName: String
    let shortName: String
    let glyph: String
    let symbolName: String
    let logoAssetName: String?
    /// Desktop apps that "Open …" in the menu may launch, in preference order.
    var appBundleIdentifiers: [String] = []

    static func of(_ id: ProviderID) -> ProviderBranding {
        switch id {
        case .codex:
            return ProviderBranding(displayName: "Codex", shortName: "Codex", glyph: "✦",
                                    symbolName: "chevron.left.forwardslash.chevron.right", logoAssetName: nil,
                                    appBundleIdentifiers: ["com.openai.codex"])
        case .claude:
            return ProviderBranding(displayName: "Claude Code", shortName: "Claude", glyph: "◈",
                                    symbolName: "asterisk", logoAssetName: nil,
                                    appBundleIdentifiers: ["com.anthropic.claudefordesktop"])
        default:
            return ProviderBranding(displayName: id.rawValue.capitalized, shortName: id.rawValue.capitalized,
                                    glyph: "●", symbolName: "circle.dotted", logoAssetName: nil)
        }
    }
}
