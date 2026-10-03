import Foundation

/// Pure parsing of Codex data into normalized values. Shared by the
/// app-server client (camelCase JSON-RPC payloads) and the session log reader
/// (snake_case `token_count` events).
enum CodexParsers {
    // MARK: Rate limits

    /// Parses one rate-limit snapshot (`primary` / `secondary` windows).
    /// Accepts both the app-server (camelCase) and the session log (snake_case) shapes.
    static func windows(fromRateLimitSnapshot snapshot: [String: Any], observedAt: Date,
                        idPrefix: String = "", nameOverride: String? = nil) -> [UsageWindow] {
        ["primary", "secondary"].compactMap { key in
            guard let raw = LooseJSON.dict(snapshot[key]) else { return nil }
            let duration = LooseJSON.int(raw["windowDurationMins"] ?? raw["window_minutes"])
            let used = LooseJSON.double(raw["usedPercent"] ?? raw["used_percent"])
            var resetsAt = LooseJSON.date(raw["resetsAt"] ?? raw["resets_at"])
            if resetsAt == nil, let seconds = LooseJSON.double(raw["resets_in_seconds"] ?? raw["resetsInSeconds"]) {
                // Older Codex versions logged a relative reset.
                resetsAt = observedAt.addingTimeInterval(seconds)
            }
            guard used != nil || resetsAt != nil else { return nil }

            let isExtraBucket = nameOverride != nil
            let kind: WindowKind = isExtraBucket ? .other : WindowKind.classify(durationMinutes: duration)
            var names = UsageWindow.defaultNames(kind: WindowKind.classify(durationMinutes: duration), durationMinutes: duration)
            if let nameOverride {
                names = ("\(nameOverride) (\(names.name.lowercased()))", names.short)
            }
            return UsageWindow(
                id: idPrefix + key,
                name: names.name,
                shortName: names.short,
                kind: kind,
                durationMinutes: duration,
                usedPercent: used.map { max(0, $0) },
                resetsAt: resetsAt
            )
        }
    }

    struct RateLimitResult: Equatable {
        var windows: [UsageWindow]
        var plan: String?
        var creditsBalance: String?
    }

    /// Parses the `account/rateLimits/read` result.
    static func rateLimitsResponse(_ result: [String: Any], observedAt: Date) -> RateLimitResult? {
        var primarySnapshot = LooseJSON.dict(result["rateLimits"])
        let buckets = LooseJSON.dict(result["rateLimitsByLimitId"]) ?? [:]
        if let codexBucket = LooseJSON.dict(buckets["codex"]) {
            primarySnapshot = codexBucket
        }
        guard let snapshot = primarySnapshot else { return nil }

        var windows = self.windows(fromRateLimitSnapshot: snapshot, observedAt: observedAt)
        let primaryID = LooseJSON.string(snapshot["limitId"]) ?? "codex"
        for (limitID, value) in buckets.sorted(by: { $0.key < $1.key }) where limitID != primaryID {
            guard let bucket = LooseJSON.dict(value) else { continue }
            let name = LooseJSON.string(bucket["limitName"]) ?? limitID
            windows += self.windows(fromRateLimitSnapshot: bucket, observedAt: observedAt,
                                    idPrefix: "\(limitID).", nameOverride: name)
        }
        return RateLimitResult(
            windows: windows,
            plan: LooseJSON.string(snapshot["planType"]).map(planDisplayName),
            creditsBalance: creditsText(LooseJSON.dict(snapshot["credits"]))
        )
    }

    static func creditsText(_ credits: [String: Any]?) -> String? {
        guard let credits else { return nil }
        if LooseJSON.bool(credits["unlimited"]) == true { return "Unlimited" }
        guard LooseJSON.bool(credits["hasCredits"] ?? credits["has_credits"]) == true,
              let balance = LooseJSON.string(credits["balance"]) ?? LooseJSON.double(credits["balance"]).map({ String($0) })
        else { return nil }
        return balance
    }

    static func planDisplayName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite": return "Pro Lite"
        case "free": return "Free"
        case "go": return "Go"
        case "team": return "Team"
        case "business", "self_serve_business_usage_based": return "Business"
        case "enterprise", "enterprise_cbp_usage_based": return "Enterprise"
        case "edu": return "Edu"
        case "unknown": return "Unknown"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    enum AccountState: Equatable {
        case signedIn(plan: String?)
        case apiKey
        case signedOut
        case unknown
    }

    /// Parses the `account/read` result. Only the plan is kept; the e-mail address is ignored.
    static func accountState(_ result: [String: Any]) -> AccountState {
        guard let account = LooseJSON.dict(result["account"]) else {
            return LooseJSON.bool(result["requiresOpenaiAuth"]) == true ? .signedOut : .unknown
        }
        switch LooseJSON.string(account["type"]) {
        case "chatgpt": return .signedIn(plan: LooseJSON.string(account["planType"]).map(planDisplayName))
        case "apiKey": return .apiKey
        case .some: return .signedIn(plan: nil)
        case nil: return .unknown
        }
    }

    // MARK: Session log

    struct SessionLogSummary: Equatable {
        var windows: [UsageWindow] = []
        var rateLimitsObservedAt: Date?
        var plan: String?
        var session = SessionInfo()
    }

    /// Extracts metadata from rollout JSONL lines (oldest first). Only numeric
    /// counters, model names, timestamps and the working directory are read;
    /// message contents are never inspected or kept.
    static func summarizeSessionLog<S: StringProtocol>(lines: [S]) -> SessionLogSummary {
        var summary = SessionLogSummary()
        var foundTokens = false, foundLimits = false, foundContext = false

        for line in lines.reversed() {
            // Cheap pre-filter: skip lines that cannot be one of the events we read.
            guard line.contains("\"token_count\"") || line.contains("\"turn_context\"")
                || line.contains("\"session_meta\"") else { continue }
            guard let event = LooseJSON.object(line: line) else { continue }
            let timestamp = LooseJSON.date(event["timestamp"])
            let type = LooseJSON.string(event["type"])
            let payload = LooseJSON.dict(event["payload"]) ?? [:]

            if summary.session.lastActivity == nil, let timestamp { summary.session.lastActivity = timestamp }

            if type == "event_msg", LooseJSON.string(payload["type"]) == "token_count" {
                if !foundTokens, let info = LooseJSON.dict(payload["info"]) {
                    foundTokens = true
                    let total = LooseJSON.dict(info["total_token_usage"]) ?? [:]
                    summary.session.inputTokens = LooseJSON.int(total["input_tokens"])
                    summary.session.outputTokens = LooseJSON.int(total["output_tokens"])
                    summary.session.cachedInputTokens = LooseJSON.int(total["cached_input_tokens"])
                    if let window = LooseJSON.int(info["model_context_window"]), window > 0 {
                        summary.session.contextWindowTokens = window
                        let last = LooseJSON.dict(info["last_token_usage"]) ?? [:]
                        if let used = LooseJSON.int(last["total_tokens"]) ?? LooseJSON.int(last["input_tokens"]) {
                            summary.session.contextUsedPercent = min(100, Double(used) / Double(window) * 100)
                        }
                    }
                }
                if !foundLimits, let limits = LooseJSON.dict(payload["rate_limits"]) {
                    let observed = timestamp ?? Date()
                    let windows = self.windows(fromRateLimitSnapshot: limits, observedAt: observed)
                    if !windows.isEmpty {
                        foundLimits = true
                        summary.windows = windows
                        summary.rateLimitsObservedAt = observed
                        summary.plan = LooseJSON.string(limits["plan_type"]).map(planDisplayName)
                    }
                }
            } else if type == "turn_context", !foundContext {
                foundContext = true
                summary.session.model = LooseJSON.string(payload["model"])
                summary.session.workingDirectory = LooseJSON.string(payload["cwd"])
            } else if type == "session_meta", summary.session.workingDirectory == nil {
                summary.session.workingDirectory = LooseJSON.string(payload["cwd"])
            }
            if foundTokens && foundLimits && foundContext { break }
        }
        return summary
    }
}
