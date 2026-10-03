import XCTest
@testable import AIUsage

final class MenuBarFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ id: ProviderID = .codex, session: Double? = 72, weekly: Double? = 34,
                          observedAgo: TimeInterval = 0, status: ProviderStatus = .ok) -> UsageSnapshot {
        var s = UsageSnapshot(provider: id, status: status, refreshedAt: now)
        if let session {
            s.windows.append(UsageWindow(id: "primary", name: "5 hour", shortName: "5h", kind: .session,
                                         durationMinutes: 300, usedPercent: session,
                                         resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)))
        }
        if let weekly {
            s.windows.append(UsageWindow(id: "secondary", name: "Weekly", shortName: "W", kind: .weekly,
                                         durationMinutes: 10080, usedPercent: weekly,
                                         resetsAt: now.addingTimeInterval(3 * 86400)))
        }
        s.rateLimitsObservedAt = now.addingTimeInterval(-observedAgo)
        return s
    }

    private func options(_ display: [ProviderID: ProviderDisplaySettings] = [:], showUnavailable: Bool = false)
        -> MenuBarFormatter.Options {
        .init(order: [.codex, .claude], display: display, showUnavailableProviders: showUnavailable, staleAfter: 1800)
    }

    func testDefaultShowsGlyphAndSessionUsage() {
        let items = MenuBarFormatter.items(snapshots: [.codex: snapshot()], options: options(), now: now)
        XCTAssertEqual(items, [MenuBarItem(provider: .codex, icon: .text("✦"), text: "72%", dimmed: false)])
    }

    func testRemainingWithLabelAndCountdown() {
        var settings = ProviderDisplaySettings()
        settings.valueMode = .remaining
        settings.showWindowLabel = true
        settings.showResetCountdown = true
        let items = MenuBarFormatter.items(snapshots: [.codex: snapshot()], options: options([.codex: settings]), now: now)
        XCTAssertEqual(items.first?.text, "5h 28% 2h14m")
    }

    func testSecondaryWindow() {
        var settings = ProviderDisplaySettings()
        settings.secondaryWindow = .weekly
        let items = MenuBarFormatter.items(snapshots: [.codex: snapshot()], options: options([.codex: settings]), now: now)
        XCTAssertEqual(items.first?.text, "72% · 34%")
    }

    func testMostConstrainedPicksHighest() {
        var settings = ProviderDisplaySettings()
        settings.primaryWindow = .mostConstrained
        let items = MenuBarFormatter.items(snapshots: [.codex: snapshot(session: 10, weekly: 90)],
                                           options: options([.codex: settings]), now: now)
        XCTAssertEqual(items.first?.text, "90%")
    }

    func testOnlyWeeklyWindowExists() {
        let items = MenuBarFormatter.items(snapshots: [.codex: snapshot(session: nil, weekly: 40)], options: options(), now: now)
        XCTAssertEqual(items.first?.text, MenuBarFormatter.placeholder)
    }

    func testStaleDataIsDimmed() {
        let items = MenuBarFormatter.items(snapshots: [.codex: snapshot(observedAgo: 3600)], options: options(), now: now)
        XCTAssertEqual(items.first?.dimmed, true)
        XCTAssertEqual(items.first?.text, "72%")
    }

    func testUnavailableProviderHiddenByDefault() {
        let snapshots: [ProviderID: UsageSnapshot] = [.claude: .empty(.claude, status: .notInstalled, at: now)]
        XCTAssertTrue(MenuBarFormatter.items(snapshots: snapshots, options: options(), now: now).isEmpty)
        let shown = MenuBarFormatter.items(snapshots: snapshots, options: options(showUnavailable: true), now: now)
        XCTAssertEqual(shown.first?.text, MenuBarFormatter.placeholder)
        XCTAssertEqual(shown.first?.dimmed, true)
    }

    func testFailureIsNeverRenderedAsZero() {
        let snapshots: [ProviderID: UsageSnapshot] = [.codex: .empty(.codex, status: .error("boom"), at: now)]
        let shown = MenuBarFormatter.items(snapshots: snapshots, options: options(showUnavailable: true), now: now)
        XCTAssertNotEqual(shown.first?.text, "0%")
    }

    func testResetWindowDoesNotShowOldPercentage() {
        var s = snapshot()
        s.windows[0].resetsAt = now.addingTimeInterval(-60)
        let items = MenuBarFormatter.items(snapshots: [.codex: s], options: options(), now: now)
        XCTAssertEqual(items.first?.text, MenuBarFormatter.placeholder)
    }

    func testIconOnlyAndHiddenProviders() {
        var codex = ProviderDisplaySettings()
        codex.content = .iconOnly
        codex.iconStyle = .sparkle
        var claude = ProviderDisplaySettings()
        claude.showInMenuBar = false
        let items = MenuBarFormatter.items(
            snapshots: [.codex: snapshot(), .claude: snapshot(.claude)],
            options: options([.codex: codex, .claude: claude]), now: now)
        XCTAssertEqual(items, [MenuBarItem(provider: .codex, icon: .symbol("sparkle"), text: nil, dimmed: false)])
    }

    func testIconOnlyWithoutIconFallsBackToName() {
        var settings = ProviderDisplaySettings()
        settings.content = .iconOnly
        settings.iconStyle = .none
        let items = MenuBarFormatter.items(snapshots: [.codex: snapshot()], options: options([.codex: settings]), now: now)
        XCTAssertEqual(items.first?.text, "Codex")
    }

    func testPercentageUnavailableButResetKnown() {
        var s = snapshot(weekly: nil)
        s.windows[0].usedPercent = nil
        var settings = ProviderDisplaySettings()
        settings.showResetCountdown = true
        let items = MenuBarFormatter.items(snapshots: [.codex: s], options: options([.codex: settings]), now: now)
        XCTAssertEqual(items.first?.text, "2h14m")
    }
}
