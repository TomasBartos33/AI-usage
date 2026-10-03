import Foundation

/// Stable identifier of a usage provider. A struct (not an enum) so new providers
/// can be added without touching every `switch` in the UI.
struct ProviderID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    var description: String { rawValue }

    static let codex = ProviderID("codex")
    static let claude = ProviderID("claude")

    /// Providers known to the app, in default menu bar order.
    static let builtIn: [ProviderID] = [.codex, .claude]
}

/// Semantic category of a rate-limit window. Providers report windows with
/// arbitrary durations; the kind lets the UI pick "the 5 hour one" or "the weekly one"
/// without assuming every provider has exactly those two.
enum WindowKind: String, Codable, Sendable, CaseIterable {
    case session   // short rolling window, typically 5 hours
    case weekly    // 7 day window
    case other     // anything else (model-specific, monthly spend, ...)

    /// Classifies a window by its duration in minutes.
    static func classify(durationMinutes: Int?) -> WindowKind {
        guard let minutes = durationMinutes else { return .other }
        switch minutes {
        case 1...(24 * 60): return .session
        case (6 * 24 * 60)...(8 * 24 * 60): return .weekly
        default: return .other
        }
    }
}

struct UsageWindow: Codable, Hashable, Identifiable, Sendable {
    /// Stable key within a provider, e.g. `primary`, `five_hour`, `seven_day_opus`.
    var id: String
    /// Human readable name for the detail panel, e.g. "5 hour".
    var name: String
    /// Compact label for the menu bar, e.g. "5h", "W".
    var shortName: String
    var kind: WindowKind
    var durationMinutes: Int?
    /// 0...100 (may exceed 100 for spend limits). `nil` when the provider only reported a reset time.
    var usedPercent: Double?
    var resetsAt: Date?

    var remainingPercent: Double? {
        usedPercent.map { max(0, 100 - $0) }
    }

    /// A window whose reset time has passed no longer describes current usage.
    func hasReset(at now: Date) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }

    static func defaultNames(kind: WindowKind, durationMinutes: Int?) -> (name: String, short: String) {
        switch kind {
        case .session:
            if let m = durationMinutes, m % 60 == 0 {
                return ("\(m / 60) hour", "\(m / 60)h")
            }
            return ("Session", "S")
        case .weekly:
            return ("Weekly", "W")
        case .other:
            if let m = durationMinutes {
                if m % (24 * 60) == 0 { return ("\(m / (24 * 60)) day", "\(m / (24 * 60))d") }
                if m % 60 == 0 { return ("\(m / 60) hour", "\(m / 60)h") }
                return ("\(m) min", "\(m)m")
            }
            return ("Limit", "L")
        }
    }
}

/// Availability of a provider. Freshness of data is tracked separately (see `Freshness`).
enum ProviderStatus: Codable, Equatable, Sendable {
    case ok
    case notInstalled
    case notAuthenticated
    /// Installed, but nothing has been recorded yet (e.g. never used).
    case noData
    case error(String)

    var isProblem: Bool {
        switch self {
        case .ok: return false
        default: return true
        }
    }

    var summary: String {
        switch self {
        case .ok: return "Available"
        case .notInstalled: return "Not installed"
        case .notAuthenticated: return "Not signed in"
        case .noData: return "No usage recorded yet"
        case .error(let message): return message
        }
    }
}

/// Where a piece of data came from. Shown in the detail panel so the user
/// knows whether a value is live server data or a locally cached copy.
enum DataSource: String, Codable, Sendable {
    case codexAppServer
    case codexSessionLog
    case claudeUsageCache
    case claudeStatusLine
    case claudeTranscript
    case demo

    var displayName: String {
        switch self {
        case .codexAppServer: return "Codex app-server"
        case .codexSessionLog: return "Codex session log"
        case .claudeUsageCache: return "Claude Code usage cache"
        case .claudeStatusLine: return "Claude Code status line"
        case .claudeTranscript: return "Claude Code transcript"
        case .demo: return "Demo data"
        }
    }
}

enum Freshness: Equatable, Sendable {
    case fresh
    case stale
    case unknown
}

/// Metadata about the most recently active local session of a tool.
struct SessionInfo: Codable, Equatable, Sendable {
    var model: String?
    var contextUsedPercent: Double?
    /// Tokens currently in the context window (when the percentage is unknown).
    var contextTokens: Int?
    var contextWindowTokens: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var cachedInputTokens: Int?
    var costUSD: Decimal?
    var workingDirectory: String?
    var lastActivity: Date?

    var isEmpty: Bool {
        model == nil && contextUsedPercent == nil && contextTokens == nil && inputTokens == nil && outputTokens == nil
            && costUSD == nil && workingDirectory == nil && lastActivity == nil
    }
}

/// Account level metadata.
struct AccountInfo: Codable, Equatable, Sendable {
    var plan: String?
    var creditsBalance: String?
}

/// Normalized provider state. The UI only consumes this type, never provider-specific JSON.
struct UsageSnapshot: Codable, Equatable, Sendable {
    var provider: ProviderID
    var status: ProviderStatus
    /// When this snapshot was assembled (not when the underlying data was produced).
    var refreshedAt: Date

    var windows: [UsageWindow] = []
    /// When the provider produced the rate-limit data in `windows`.
    var rateLimitsObservedAt: Date?
    var rateLimitsSource: DataSource?

    var session: SessionInfo?
    var sessionSource: DataSource?

    var account: AccountInfo?
    /// Optional explanatory text (e.g. why rate limits are unavailable).
    var note: String?

    func window(_ kind: WindowKind) -> UsageWindow? {
        windows.first { $0.kind == kind }
    }

    /// The window with the highest used percentage that has not reset yet.
    func mostConstrainedWindow(at now: Date) -> UsageWindow? {
        windows
            .filter { !$0.hasReset(at: now) && $0.usedPercent != nil }
            .max { ($0.usedPercent ?? 0) < ($1.usedPercent ?? 0) }
    }

    func freshness(at now: Date, staleAfter: TimeInterval) -> Freshness {
        guard let observed = rateLimitsObservedAt else { return .unknown }
        return now.timeIntervalSince(observed) > staleAfter ? .stale : .fresh
    }

    static func empty(_ provider: ProviderID, status: ProviderStatus, at date: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(provider: provider, status: status, refreshedAt: date)
    }
}

/// Metrics a provider may be able to report. The settings UI only offers
/// metrics present in the provider's capability set.
enum Metric: String, CaseIterable, Codable, Sendable {
    case sessionWindow
    case weeklyWindow
    case resetTime
    case plan
    case credits
    case model
    case contextUsage
    case sessionTokens
    case sessionCost
    case workingDirectory
    case lastActivity

    var displayName: String {
        switch self {
        case .sessionWindow: return "5 hour usage"
        case .weeklyWindow: return "Weekly usage"
        case .resetTime: return "Reset time"
        case .plan: return "Plan"
        case .credits: return "Credits"
        case .model: return "Current model"
        case .contextUsage: return "Context usage"
        case .sessionTokens: return "Session tokens"
        case .sessionCost: return "Session cost"
        case .workingDirectory: return "Project"
        case .lastActivity: return "Last activity"
        }
    }
}

struct ProviderCapabilities: Sendable, Equatable {
    var metrics: Set<Metric>

    func supports(_ metric: Metric) -> Bool { metrics.contains(metric) }

    var supportsRateLimits: Bool { supports(.sessionWindow) || supports(.weeklyWindow) }
}
