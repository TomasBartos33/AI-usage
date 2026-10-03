import Foundation

/// Claude Code usage from local, non-inference sources:
///
/// 1. **Usage cache** in `~/.claude.json` (`cachedUsageUtilization`): Claude
///    Code itself fetches the account's 5 hour / weekly utilization and caches
///    it with a fetch timestamp. AI-usage only reads that cache.
/// 2. **Status line bridge** (optional, see `ClaudeStatusLineBridge`): rate
///    limits, model, context window and session cost as of the last assistant
///    message.
/// 3. **Transcripts** (`~/.claude/projects/*/*.jsonl`): model, token counters,
///    working directory and last activity of the most recent session.
///
/// Usage is only known after Claude Code has done something; AI-usage shows
/// the last known value with its timestamp and never asks for fresh data.
actor ClaudeProvider: UsageProvider {
    nonisolated let id = ProviderID.claude
    nonisolated let displayName = "Claude Code"
    nonisolated let capabilities = ProviderCapabilities(metrics: [
        .sessionWindow, .weeklyWindow, .resetTime, .plan,
        .model, .contextUsage, .sessionTokens, .sessionCost, .workingDirectory, .lastActivity,
    ])

    nonisolated var watchedDirectories: [URL] { [ClaudePaths.projectsDirectory] }
    nonisolated let watchedFiles: [URL]

    private let liveUsage: Bool
    private var lastLiveQuery: Date?
    private var lastLive: (windows: [UsageWindow], observedAt: Date)?
    private var liveError: String?

    init(watchBridge: Bool, liveUsage: Bool) {
        self.liveUsage = liveUsage
        // The bridge snapshot is only watched when the bridge is installed, to
        // avoid waiting on a file that will never appear.
        watchedFiles = [ClaudePaths.globalStateFile] + (watchBridge ? [ClaudePaths.bridgeSnapshotFile] : [])
    }

    private var activeTranscript: URL?
    private var transcript = TranscriptAccumulator()

    func noteChangedPaths(_ paths: [String]) async {
        if let path = paths.last(where: { ClaudePaths.isTranscript(URL(fileURLWithPath: $0)) }) {
            activeTranscript = URL(fileURLWithPath: path)
        }
    }

    func refresh(trigger: RefreshTrigger, previous: UsageSnapshot?) async -> UsageSnapshot {
        let now = Date()
        guard ClaudePaths.isInstalled else { return .empty(id, status: .notInstalled, at: now) }
        var snapshot = UsageSnapshot(provider: id, status: .ok, refreshedAt: now)

        // 1. Usage cache + account plan from the global state file.
        let globalState = (try? Data(contentsOf: ClaudePaths.globalStateFile)).flatMap(LooseJSON.object)
        let account = globalState.map(ClaudeParsers.accountState(fromGlobalState:)) ?? .noOAuthAccount
        let cache = globalState.flatMap(ClaudeParsers.usageCache(fromGlobalState:))

        // 2. Status line bridge snapshot.
        let bridgeDate = modificationDate(ClaudePaths.bridgeSnapshotFile)
        let statusLine = (try? Data(contentsOf: ClaudePaths.bridgeSnapshotFile))
            .flatMap(LooseJSON.object)
            .map(ClaudeParsers.statusLine)

        // 3. Transcript of the most recent session.
        if let file = latestTranscript(trigger: trigger) {
            transcript.update(from: file)
        }

        // 4. Optional live query of Anthropic's usage endpoint (metadata only, throttled).
        if liveUsage, account != .noOAuthAccount, shouldQueryLive(trigger: trigger, now: now) {
            lastLiveQuery = now
            do {
                let windows = try await ClaudeUsageAPI().fetchWindows()
                if !windows.isEmpty { lastLive = (windows, Date()) }
                liveError = nil
            } catch {
                liveError = error.localizedDescription
            }
        }

        // Rate limits: newest observation wins, falling back to the last known value.
        var candidates: [(windows: [UsageWindow], observedAt: Date, source: DataSource)] = []
        if let lastLive {
            candidates.append((lastLive.windows, lastLive.observedAt, .claudeUsageAPI))
        }
        if let cache, !cache.windows.isEmpty {
            candidates.append((cache.windows, cache.fetchedAt ?? modificationDate(ClaudePaths.globalStateFile) ?? now, .claudeUsageCache))
        }
        if let statusLine, !statusLine.windows.isEmpty, let bridgeDate {
            candidates.append((statusLine.windows, bridgeDate, .claudeStatusLine))
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

        // Session details: transcript counters, enriched by the status line when it is current.
        var session = transcript.sessionInfo
        var sessionSource: DataSource? = session == nil ? nil : .claudeTranscript
        if let statusLine, let bridgeDate, !statusLine.session.isEmpty {
            let transcriptActivity = session?.lastActivity ?? .distantPast
            if bridgeDate >= transcriptActivity.addingTimeInterval(-120) {
                var merged = session ?? SessionInfo()
                let live = statusLine.session
                merged.model = live.model ?? merged.model
                merged.contextUsedPercent = live.contextUsedPercent ?? merged.contextUsedPercent
                merged.contextWindowTokens = live.contextWindowTokens ?? merged.contextWindowTokens
                merged.costUSD = live.costUSD ?? merged.costUSD
                merged.workingDirectory = live.workingDirectory ?? merged.workingDirectory
                merged.lastActivity = max(merged.lastActivity ?? bridgeDate, bridgeDate)
                session = merged
                sessionSource = sessionSource ?? .claudeStatusLine
            }
        }
        if session == nil, let previousSession = previous?.session, previous?.sessionSource != .demo {
            session = previousSession
            sessionSource = previous?.sessionSource
        }
        snapshot.session = session
        snapshot.sessionSource = sessionSource

        // Account / status.
        switch account {
        case .subscription(let plan):
            if let plan { snapshot.account = AccountInfo(plan: plan) }
            if snapshot.windows.isEmpty {
                snapshot.note = "Rate limits appear after Claude Code has been used (Pro/Max plans)."
            }
        case .noOAuthAccount:
            if snapshot.windows.isEmpty {
                snapshot.note = "Claude Code reports usage limits only for Claude Pro/Max sign-in."
            }
        }
        if let liveError, snapshot.note == nil {
            snapshot.note = liveError
        }
        if snapshot.windows.isEmpty && snapshot.session == nil {
            snapshot.status = account == .noOAuthAccount && globalState != nil ? .notAuthenticated : .noData
        }
        return snapshot
    }

    /// Same cadence as Codex: launch, timer, reset, manual; menu opens at most every 2 minutes.
    private func shouldQueryLive(trigger: RefreshTrigger, now: Date) -> Bool {
        guard trigger.allowsMetadataQuery else { return false }
        guard let lastLiveQuery else { return true }
        let elapsed = now.timeIntervalSince(lastLiveQuery)
        switch trigger {
        case .menuOpened: return elapsed >= 120
        case .manual: return elapsed >= 10
        default: return elapsed >= 30
        }
    }

    private func latestTranscript(trigger: RefreshTrigger) -> URL? {
        if trigger == .fileChange, let activeTranscript, FileManager.default.fileExists(atPath: activeTranscript.path) {
            return activeTranscript
        }
        let scanned = ClaudePaths.latestTranscript()
        let candidates = [activeTranscript, scanned].compactMap { $0 }
        let newest = candidates.max { (modificationDate($0) ?? .distantPast) < (modificationDate($1) ?? .distantPast) }
        activeTranscript = newest
        return newest
    }

    private func modificationDate(_ url: URL) -> Date? {
        FileInfo.modificationDate(url)
    }
}
