import Foundation

/// Pure parsing of Claude Code's local data into normalized values.
enum ClaudeParsers {
    // MARK: Usage cache (~/.claude.json)

    struct UsageCache: Equatable {
        var windows: [UsageWindow]
        var fetchedAt: Date?
    }

    /// Known utilization buckets with readable names. Unknown (often code-named)
    /// buckets are ignored rather than shown with confusing labels.
    private static let knownBuckets: [(key: String, name: String, short: String, kind: WindowKind, minutes: Int)] = [
        ("five_hour", "5 hour", "5h", .session, 300),
        ("seven_day", "Weekly", "W", .weekly, 10080),
        ("seven_day_opus", "Weekly (Opus)", "WO", .other, 10080),
        ("seven_day_sonnet", "Weekly (Sonnet)", "WS", .other, 10080),
    ]

    /// Parses `cachedUsageUtilization` from Claude Code's global state file. Claude Code
    /// fetches this from Anthropic's usage endpoint itself; AI-usage only reads the cache.
    static func usageCache(fromGlobalState state: [String: Any]) -> UsageCache? {
        guard let cache = LooseJSON.dict(state["cachedUsageUtilization"]),
              let utilization = LooseJSON.dict(cache["utilization"]) else { return nil }
        let windows: [UsageWindow] = knownBuckets.compactMap { bucket in
            guard let raw = LooseJSON.dict(utilization[bucket.key]) else { return nil }
            let used = LooseJSON.double(raw["utilization"])
            let resetsAt = LooseJSON.date(raw["resets_at"])
            guard used != nil || resetsAt != nil else { return nil }
            return UsageWindow(id: bucket.key, name: bucket.name, shortName: bucket.short, kind: bucket.kind,
                               durationMinutes: bucket.minutes, usedPercent: used.map { max(0, $0) }, resetsAt: resetsAt)
        }
        return UsageCache(windows: windows, fetchedAt: LooseJSON.date(cache["fetchedAtMs"]))
    }

    enum AccountState: Equatable {
        case subscription(plan: String?)
        case noOAuthAccount
    }

    /// Reads only the plan type from `oauthAccount`; identity fields are ignored.
    static func accountState(fromGlobalState state: [String: Any]) -> AccountState {
        guard let account = LooseJSON.dict(state["oauthAccount"]) else { return .noOAuthAccount }
        let raw = LooseJSON.string(account["organizationType"]) ?? LooseJSON.string(account["seatTier"])
        return .subscription(plan: raw.map(planDisplayName))
    }

    static func planDisplayName(_ raw: String) -> String {
        var name = raw.lowercased()
        if name.hasPrefix("claude_") { name.removeFirst("claude_".count) }
        switch name {
        case "pro": return "Pro"
        case "max": return "Max"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: Status line snapshot (written by the optional bridge)

    struct StatusLine: Equatable {
        var windows: [UsageWindow] = []
        var session = SessionInfo()
        var sessionID: String?
    }

    /// Parses the sanitized status line JSON (Claude Code's documented status line schema).
    static func statusLine(_ json: [String: Any]) -> StatusLine {
        var result = StatusLine()
        result.sessionID = LooseJSON.string(json["session_id"])

        if let limits = LooseJSON.dict(json["rate_limits"]) {
            let buckets: [(String, String, String, WindowKind, Int?)] = [
                ("five_hour", "5 hour", "5h", .session, 300),
                ("seven_day", "Weekly", "W", .weekly, 10080),
                ("spend_limit", "Spend limit", "$", .other, nil),
            ]
            for (key, name, short, kind, minutes) in buckets {
                guard let raw = LooseJSON.dict(limits[key]) else { continue }
                let used = LooseJSON.double(raw["used_percentage"])
                let resetsAt = LooseJSON.date(raw["resets_at"])
                guard used != nil || resetsAt != nil else { continue }
                result.windows.append(UsageWindow(id: key, name: name, shortName: short, kind: kind,
                                                  durationMinutes: minutes, usedPercent: used.map { max(0, $0) },
                                                  resetsAt: resetsAt))
            }
        }

        let model = LooseJSON.dict(json["model"])
        result.session.model = LooseJSON.string(model?["id"]) ?? LooseJSON.string(model?["display_name"])

        if let context = LooseJSON.dict(json["context_window"]) {
            result.session.contextUsedPercent = LooseJSON.double(context["used_percentage"])
            result.session.contextWindowTokens = LooseJSON.int(context["context_window_size"])
        }
        if let cost = LooseJSON.dict(json["cost"]), let usd = LooseJSON.double(cost["total_cost_usd"]) {
            result.session.costUSD = Decimal(string: String(format: "%.4f", usd))
        }
        result.session.workingDirectory = LooseJSON.string(json["cwd"])
            ?? LooseJSON.string(LooseJSON.dict(json["workspace"])?["current_dir"])
        return result
    }

    // MARK: Transcripts

    struct TranscriptEntry: Equatable {
        var messageID: String?
        var model: String?
        var timestamp: Date?
        var workingDirectory: String?
        var inputTokens: Int
        var cacheCreationTokens: Int
        var cacheReadTokens: Int
        var outputTokens: Int
        var isSidechain: Bool

        /// Tokens the request sent as context (input + cache writes + cache reads).
        var contextTokens: Int { inputTokens + cacheCreationTokens + cacheReadTokens }
    }

    /// Parses one transcript line. Returns nil for anything that isn't an
    /// assistant message with usage. Message contents are never read.
    static func transcriptEntry<S: StringProtocol>(line: S) -> TranscriptEntry? {
        guard line.contains("\"assistant\""), line.contains("\"usage\"") else { return nil }
        guard let json = LooseJSON.object(line: line), LooseJSON.string(json["type"]) == "assistant",
              let message = LooseJSON.dict(json["message"]), let usage = LooseJSON.dict(message["usage"]) else { return nil }
        let model = LooseJSON.string(message["model"])
        return TranscriptEntry(
            messageID: LooseJSON.string(message["id"]) ?? LooseJSON.string(json["requestId"]),
            model: model == "<synthetic>" ? nil : model,
            timestamp: LooseJSON.date(json["timestamp"]),
            workingDirectory: LooseJSON.string(json["cwd"]),
            inputTokens: LooseJSON.int(usage["input_tokens"]) ?? 0,
            cacheCreationTokens: LooseJSON.int(usage["cache_creation_input_tokens"]) ?? 0,
            cacheReadTokens: LooseJSON.int(usage["cache_read_input_tokens"]) ?? 0,
            outputTokens: LooseJSON.int(usage["output_tokens"]) ?? 0,
            isSidechain: LooseJSON.bool(json["isSidechain"]) ?? false
        )
    }
}

/// Incrementally aggregates one transcript file. Keeps a byte offset so each
/// refresh only parses newly appended lines.
struct TranscriptAccumulator {
    private(set) var file: URL?
    private(set) var offset: UInt64 = 0
    private var seenMessages = Set<String>()
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0
    private(set) var cachedInputTokens = 0
    private(set) var lastModel: String?
    private(set) var lastTimestamp: Date?
    private(set) var workingDirectory: String?
    private(set) var lastContextTokens: Int?

    /// Reads new data from `url`. Starts over when the file changes or shrinks.
    mutating func update(from url: URL, maxInitialBytes: UInt64 = 64 * 1_048_576) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return }
        if url != file || size < offset {
            self = TranscriptAccumulator()
            file = url
            // Very large transcripts: only aggregate the most recent part.
            offset = size > maxInitialBytes ? size - maxInitialBytes : 0
        }
        guard size > offset, (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else { return }
        // Only consume complete lines; a partially written last line is read next time.
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return }
        let complete = data[data.startIndex...lastNewline]
        offset += UInt64(complete.count)
        for line in String(decoding: complete, as: UTF8.self).split(separator: "\n") {
            guard let entry = ClaudeParsers.transcriptEntry(line: line) else { continue }
            ingest(entry)
        }
    }

    mutating func ingest(_ entry: ClaudeParsers.TranscriptEntry) {
        // One API response is split over several lines that repeat the same usage.
        if let id = entry.messageID {
            guard seenMessages.insert(id).inserted else { return }
        }
        inputTokens += entry.contextTokens
        cachedInputTokens += entry.cacheReadTokens
        outputTokens += entry.outputTokens
        if let timestamp = entry.timestamp, timestamp >= (lastTimestamp ?? .distantPast) {
            lastTimestamp = timestamp
        }
        if !entry.isSidechain {
            if let model = entry.model { lastModel = model }
            if let cwd = entry.workingDirectory { workingDirectory = cwd }
            lastContextTokens = entry.contextTokens
        }
    }

    var sessionInfo: SessionInfo? {
        guard file != nil, lastTimestamp != nil || lastModel != nil else { return nil }
        var info = SessionInfo()
        info.model = lastModel
        info.contextTokens = lastContextTokens
        info.inputTokens = inputTokens
        info.outputTokens = outputTokens
        info.cachedInputTokens = cachedInputTokens
        info.workingDirectory = workingDirectory
        info.lastActivity = lastTimestamp
        return info
    }
}
