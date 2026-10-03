import Foundation

/// How a provider is identified in the menu bar.
enum IconStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case logo         // provider logo, loaded from the provider's installed app
    case sparkle      // generic SF Symbol sparkle
    case symbol       // provider specific SF Symbol placeholder
    case glyph        // unicode glyph (✦, ◈)
    case name         // short provider name ("Codex", "Claude")
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .logo: return "Logo"
        case .sparkle: return "Sparkle"
        case .symbol: return "Provider symbol"
        case .glyph: return "Glyph"
        case .name: return "Name"
        case .none: return "None"
        }
    }
}

/// What a provider's menu bar item contains.
enum LabelContent: String, Codable, CaseIterable, Sendable, Identifiable {
    case iconAndValue
    case valueOnly
    case iconOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iconAndValue: return "Icon + usage"
        case .valueOnly: return "Usage only"
        case .iconOnly: return "Icon only"
        }
    }
}

/// Which rate-limit window a menu bar value refers to.
enum WindowSelector: String, Codable, CaseIterable, Sendable, Identifiable {
    case session
    case weekly
    case mostConstrained

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .session: return "5 hour"
        case .weekly: return "Weekly"
        case .mostConstrained: return "Highest"
        }
    }

    func resolve(in snapshot: UsageSnapshot, now: Date) -> UsageWindow? {
        switch self {
        case .session: return snapshot.window(.session)
        case .weekly: return snapshot.window(.weekly)
        case .mostConstrained: return snapshot.mostConstrainedWindow(at: now) ?? snapshot.windows.first
        }
    }
}

enum ValueMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case used
    case remaining

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .used: return "Used"
        case .remaining: return "Remaining"
        }
    }
}

/// Per-provider menu bar configuration. Decoding is lenient so adding fields
/// later never resets a user's settings.
struct ProviderDisplaySettings: Codable, Equatable, Sendable {
    var showInMenuBar: Bool = true
    var iconStyle: IconStyle = .logo
    var content: LabelContent = .iconAndValue
    var primaryWindow: WindowSelector = .session
    /// Optional second value, e.g. weekly next to 5 hour.
    var secondaryWindow: WindowSelector?
    var valueMode: ValueMode = .used
    /// "72%" vs "72".
    var showPercentSign: Bool = true
    var showWindowLabel: Bool = false
    var showResetCountdown: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProviderDisplaySettings()
        showInMenuBar = (try? c.decode(Bool.self, forKey: .showInMenuBar)) ?? d.showInMenuBar
        iconStyle = (try? c.decode(IconStyle.self, forKey: .iconStyle)) ?? d.iconStyle
        content = (try? c.decode(LabelContent.self, forKey: .content)) ?? d.content
        primaryWindow = (try? c.decode(WindowSelector.self, forKey: .primaryWindow)) ?? d.primaryWindow
        secondaryWindow = try? c.decodeIfPresent(WindowSelector.self, forKey: .secondaryWindow)
        valueMode = (try? c.decode(ValueMode.self, forKey: .valueMode)) ?? d.valueMode
        showPercentSign = (try? c.decode(Bool.self, forKey: .showPercentSign)) ?? d.showPercentSign
        showWindowLabel = (try? c.decode(Bool.self, forKey: .showWindowLabel)) ?? d.showWindowLabel
        showResetCountdown = (try? c.decode(Bool.self, forKey: .showResetCountdown)) ?? d.showResetCountdown
    }
}

/// How often providers are polled in the background. Usage normally only
/// changes while a tool is used, which file watching already catches.
enum RefreshInterval: Int, CaseIterable, Codable, Sendable, Identifiable {
    case never = 0
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case hourly = 3600

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .never: return "Only on changes"
        case .fiveMinutes: return "Every 5 minutes"
        case .fifteenMinutes: return "Every 15 minutes"
        case .thirtyMinutes: return "Every 30 minutes"
        case .hourly: return "Every hour"
        }
    }
}
