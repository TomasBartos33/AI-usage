import AppKit

/// Loads provider logos from the provider's own installed desktop app (e.g.
/// ChatGPT.app's and Claude.app's menu bar template icons). Nothing is bundled
/// with AI-usage; if the app is not installed the caller falls back to the provider's name.
@MainActor
enum ProviderLogo {
    private static var cache: [ProviderID: NSImage?] = [:]

    static func image(for id: ProviderID) -> NSImage? {
        if let cached = cache[id] { return cached }
        var result: NSImage?
        for template in ProviderBranding.of(id).logoTemplates {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: template.bundleID),
                  let bundle = Bundle(url: appURL),
                  // Picks up @2x/@3x variants automatically.
                  let image = bundle.image(forResource: template.resource) else { continue }
            image.isTemplate = true
            result = image
            break
        }
        cache[id] = result
        return result
    }
}
