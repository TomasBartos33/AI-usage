import Foundation

/// Codex usage from two non-inference sources:
///
/// 1. **Session logs** (`~/.codex/sessions/**/rollout-*.jsonl`): every turn
///    Codex appends a `token_count` event with the account's rate limits and
///    token counters. Watched with FSEvents, so updates are free and instant
///    while Codex is in use.
/// 2. **`codex app-server`** `account/rateLimits/read`: account metadata,
///    queried on launch, when the menu opens (throttled), on the optional
///    background timer and when a window resets. It returns current limits
///    even when Codex has not been used recently.
///
/// Whichever source observed the limits most recently wins.
actor CodexProvider: UsageProvider {
    nonisolated let id = ProviderID.codex
    nonisolated let displayName = "Codex"
    nonisolated let capabilities = ProviderCapabilities(metrics: [
        .sessionWindow, .weeklyWindow, .resetTime, .plan, .credits,
        .model, .contextUsage, .sessionTokens, .workingDirectory, .lastActivity,
    ])

    nonisolated var watchedDirectories: [URL] { [sessionsDirectory] }

    private let sessionsDirectory: URL
    private let executableOverride: String?
    /// Minimum time between app-server queries triggered by opening the menu.
    private let menuQueryThrottle: TimeInterval = 120

    private var activeRollout: URL?
    private var lastQuery: Date?
    private var lastServerData: ServerData?

    private struct ServerData {
        var windows: [UsageWindow]
        var observedAt: Date
        var plan: String?
        var credits: String?
    }

    init(executableOverride: String?, sessionsDirectory: URL = CodexLocator.sessionsDirectory) {
        self.executableOverride = executableOverride
        self.sessionsDirectory = sessionsDirectory
    }

    func noteChangedPaths(_ paths: [String]) async {
        // Remember which rollout is being written so resumed old sessions are followed too.
        if let path = paths.last(where: { CodexLocator.isRolloutFile(URL(fileURLWithPath: $0)) }) {
            activeRollout = URL(fileURLWithPath: path)
        }
    }

    func refresh(trigger: RefreshTrigger, previous: UsageSnapshot?) async -> UsageSnapshot {
        let now = Date()
        let executable = CodexLocator.executable(override: executableOverride)
        let hasData = FileManager.default.fileExists(atPath: CodexLocator.codexHome.path)
        guard executable != nil || hasData else {
            return .empty(id, status: .notInstalled, at: now)
        }

        var snapshot = UsageSnapshot(provider: id, status: .ok, refreshedAt: now)
        var notes: [String] = []

        // 1. Local session log.
        let log = readLatestSessionLog(trigger: trigger)
        if let log, !log.session.isEmpty {
            snapshot.session = log.session
            snapshot.sessionSource = .codexSessionLog
        }

        // 2. App-server account metadata.
        var accountState: CodexParsers.AccountState = .unknown
        if let executable, shouldQueryServer(trigger: trigger, now: now) {
            lastQuery = now
            do {
                let result = try await CodexAppServerClient(executable: executable).fetch()
                if let account = result.account { accountState = CodexParsers.accountState(account) }
                if let payload = result.rateLimits,
                   let parsed = CodexParsers.rateLimitsResponse(payload, observedAt: Date()), !parsed.windows.isEmpty {
                    lastServerData = ServerData(windows: parsed.windows, observedAt: Date(),
                                                plan: parsed.plan, credits: parsed.creditsBalance)
                } else if let message = result.rateLimitsError, accountState != .signedOut {
                    notes.append("Rate limits unavailable: \(message)")
                }
            } catch {
                notes.append(error.localizedDescription)
            }
        }

        // 3. Merge: newest rate-limit observation wins; otherwise keep the last known value.
        var candidates: [(windows: [UsageWindow], observedAt: Date, source: DataSource)] = []
        if let server = lastServerData {
            candidates.append((server.windows, server.observedAt, .codexAppServer))
        }
        if let log, let observed = log.rateLimitsObservedAt, !log.windows.isEmpty {
            candidates.append((log.windows, observed, .codexSessionLog))
        }
        if let previous, let observed = previous.rateLimitsObservedAt, !previous.windows.isEmpty,
           let source = previous.rateLimitsSource, source != .demo {
            candidates.append((previous.windows, observed, source))
        }
        if let best = candidates.max(by: { $0.observedAt < $1.observedAt }) {
            snapshot.windows = best.windows
            snapshot.rateLimitsObservedAt = best.observedAt
            snapshot.rateLimitsSource = best.source
        }

        let plan: String? = {
            if case .signedIn(let plan) = accountState, let plan { return plan }
            return lastServerData?.plan ?? log?.plan ?? previous?.account?.plan
        }()
        let credits = lastServerData?.credits
        if plan != nil || credits != nil {
            snapshot.account = AccountInfo(plan: plan, creditsBalance: credits)
        }
        if snapshot.session == nil, let previousSession = previous?.session {
            snapshot.session = previousSession
            snapshot.sessionSource = previous?.sessionSource
        }

        // 4. Status.
        switch accountState {
        case .signedOut:
            snapshot.status = .notAuthenticated
        case .apiKey:
            notes.append("Signed in with an API key: usage limits are only reported for ChatGPT sign-in.")
        default:
            break
        }
        if snapshot.status == .ok, snapshot.windows.isEmpty, snapshot.session == nil {
            snapshot.status = notes.isEmpty ? .noData : .error(notes.removeFirst())
        }
        if executable == nil {
            notes.append("Codex CLI not found; showing data from local session logs only.")
        }
        snapshot.note = notes.isEmpty ? nil : notes.joined(separator: "\n")
        return snapshot
    }

    private func shouldQueryServer(trigger: RefreshTrigger, now: Date) -> Bool {
        guard trigger.allowsMetadataQuery else { return false }
        guard let lastQuery else { return true }
        switch trigger {
        case .menuOpened:
            return now.timeIntervalSince(lastQuery) >= menuQueryThrottle
        case .timer, .windowReset, .launch:
            return now.timeIntervalSince(lastQuery) >= 30
        case .manual:
            return true
        case .fileChange:
            return false
        }
    }

    private func readLatestSessionLog(trigger: RefreshTrigger) -> CodexParsers.SessionLogSummary? {
        var candidates: [URL] = []
        if let activeRollout { candidates.append(activeRollout) }
        if trigger != .fileChange || activeRollout == nil,
           let latest = CodexLocator.latestRolloutFile(in: sessionsDirectory) {
            candidates.append(latest)
        }
        let newest = candidates.max { modificationDate($0) < modificationDate($1) }
        guard let file = newest, let lines = FileTail.lines(of: file, maxBytes: 1_048_576) else { return nil }
        activeRollout = file
        return CodexParsers.summarizeSessionLog(lines: lines)
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
