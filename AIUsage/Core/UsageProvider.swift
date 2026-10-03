import Foundation

/// Why a refresh was requested. Providers use this to decide how much work is
/// justified: a file-change refresh only re-reads local files, while an explicit
/// refresh may also ask a local tool for account metadata.
enum RefreshTrigger: String, Sendable {
    case launch
    case fileChange
    case menuOpened
    case timer
    case windowReset
    case manual

    /// Whether this trigger may query a provider's local metadata service
    /// (for example the Codex app-server). Never an inference request.
    var allowsMetadataQuery: Bool {
        switch self {
        case .fileChange: return false
        case .launch, .menuOpened, .timer, .windowReset, .manual: return true
        }
    }
}

/// A source of usage information for one AI tool.
///
/// Invariant: implementations must never send prompts or make model inference
/// requests to obtain usage. They may only read local files, or ask a locally
/// installed tool for account metadata that does not consume tokens.
protocol UsageProvider: Actor {
    nonisolated var id: ProviderID { get }
    nonisolated var displayName: String { get }
    nonisolated var capabilities: ProviderCapabilities { get }

    /// Directories whose contents changing should trigger a `.fileChange` refresh.
    nonisolated var watchedDirectories: [URL] { get }
    /// Individual files whose changes should trigger a `.fileChange` refresh.
    nonisolated var watchedFiles: [URL] { get }

    /// Builds a fresh snapshot. `previous` is the last known snapshot (possibly
    /// restored from disk) so providers can keep last-known values when a source
    /// has nothing new.
    func refresh(trigger: RefreshTrigger, previous: UsageSnapshot?) async -> UsageSnapshot

    /// Called with the paths reported by the directory watcher before a `.fileChange` refresh.
    func noteChangedPaths(_ paths: [String]) async
}

extension UsageProvider {
    nonisolated var watchedDirectories: [URL] { [] }
    nonisolated var watchedFiles: [URL] { [] }
    func noteChangedPaths(_ paths: [String]) async {}
}
