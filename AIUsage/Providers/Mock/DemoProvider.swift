import Foundation

/// Deterministic fake data for UI development and screenshots.
/// Enabled with the `--demo` launch argument or the Demo data setting.
actor DemoProvider: UsageProvider {
    nonisolated let id: ProviderID
    nonisolated let displayName: String
    nonisolated let capabilities = ProviderCapabilities(metrics: Set(Metric.allCases))

    init(id: ProviderID) {
        self.id = id
        self.displayName = ProviderBranding.of(id).displayName
    }

    func refresh(trigger: RefreshTrigger, previous: UsageSnapshot?) async -> UsageSnapshot {
        let now = Date()
        let isCodex = id == .codex
        var snapshot = UsageSnapshot(provider: id, status: .ok, refreshedAt: now)
        snapshot.windows = [
            UsageWindow(id: "session", name: "5 hour", shortName: "5h", kind: .session, durationMinutes: 300,
                        usedPercent: isCodex ? 72 : 41, resetsAt: now.addingTimeInterval(isCodex ? 8040 : 3300)),
            UsageWindow(id: "weekly", name: "Weekly", shortName: "W", kind: .weekly, durationMinutes: 10080,
                        usedPercent: isCodex ? 34 : 18, resetsAt: now.addingTimeInterval(isCodex ? 300_000 : 180_000)),
        ]
        snapshot.rateLimitsObservedAt = isCodex ? now : now.addingTimeInterval(-12 * 60)
        snapshot.rateLimitsSource = .demo
        snapshot.session = SessionInfo(
            model: isCodex ? "gpt-5-codex" : "claude-sonnet-4-5",
            contextUsedPercent: isCodex ? 23 : 61,
            contextWindowTokens: isCodex ? 272_000 : 200_000,
            inputTokens: isCodex ? 184_200 : 96_400,
            outputTokens: isCodex ? 12_800 : 7_300,
            cachedInputTokens: nil,
            costUSD: isCodex ? nil : Decimal(string: "1.84"),
            workingDirectory: "/Users/demo/Projects/ai-usage",
            lastActivity: now.addingTimeInterval(isCodex ? -90 : -12 * 60)
        )
        snapshot.sessionSource = .demo
        snapshot.account = AccountInfo(plan: isCodex ? "Plus" : "Pro", creditsBalance: nil)
        return snapshot
    }
}
