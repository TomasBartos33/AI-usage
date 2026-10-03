import XCTest
@testable import AIUsage

final class UsageModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testWindowKindClassification() {
        XCTAssertEqual(WindowKind.classify(durationMinutes: 300), .session)
        XCTAssertEqual(WindowKind.classify(durationMinutes: 10080), .weekly)
        XCTAssertEqual(WindowKind.classify(durationMinutes: 43200), .other)
        XCTAssertEqual(WindowKind.classify(durationMinutes: nil), .other)
    }

    func testRemainingPercentIsClamped() {
        let window = UsageWindow(id: "x", name: "x", shortName: "x", kind: .other, durationMinutes: nil,
                                 usedPercent: 120, resetsAt: nil)
        XCTAssertEqual(window.remainingPercent, 0)
    }

    func testFreshness() {
        var snapshot = UsageSnapshot.empty(.codex, status: .ok, at: now)
        XCTAssertEqual(snapshot.freshness(at: now, staleAfter: 600), .unknown)
        snapshot.rateLimitsObservedAt = now.addingTimeInterval(-60)
        XCTAssertEqual(snapshot.freshness(at: now, staleAfter: 600), .fresh)
        snapshot.rateLimitsObservedAt = now.addingTimeInterval(-601)
        XCTAssertEqual(snapshot.freshness(at: now, staleAfter: 600), .stale)
    }

    func testSnapshotRoundTripsThroughCache() throws {
        var snapshot = UsageSnapshot.empty(.claude, status: .error("x"), at: now)
        snapshot.windows = [UsageWindow(id: "five_hour", name: "5 hour", shortName: "5h", kind: .session,
                                        durationMinutes: 300, usedPercent: 42.5, resetsAt: now)]
        snapshot.session = SessionInfo(model: "m", costUSD: Decimal(string: "1.25"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = SnapshotCache(fileURL: url)
        cache.save([.claude: snapshot])
        XCTAssertEqual(cache.load()[.claude], snapshot)
    }

    func testDisplaySettingsDecodeLeniently() throws {
        let json = #"{"iconStyle":"sparkle","content":"bogus","futureField":1}"#
        let settings = try JSONDecoder().decode(ProviderDisplaySettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.iconStyle, .sparkle)
        XCTAssertEqual(settings.content, .iconAndValue)
        XCTAssertTrue(settings.showInMenuBar)
    }

    func testProviderOrderNormalization() {
        XCTAssertEqual(Preferences.normalizedOrder([.claude, ProviderID("unknown"), .claude]), [.claude, .codex])
        XCTAssertEqual(Preferences.normalizedOrder([]), [.codex, .claude])
    }

    func testCompactCountdown() {
        XCTAssertEqual(UsageFormatting.compactCountdown(to: now.addingTimeInterval(8040), from: now), "2h14m")
        XCTAssertEqual(UsageFormatting.compactCountdown(to: now.addingTimeInterval(45 * 60), from: now), "45m")
        XCTAssertEqual(UsageFormatting.compactCountdown(to: now.addingTimeInterval(3 * 86400 + 3600 * 4), from: now), "3d4h")
        XCTAssertEqual(UsageFormatting.compactCountdown(to: now.addingTimeInterval(-5), from: now), "now")
    }

    func testResetDescription() {
        XCTAssertEqual(UsageFormatting.resetDescription(now.addingTimeInterval(8040), now: now), "resets in 2h 14m")
        XCTAssertTrue(UsageFormatting.resetDescription(now.addingTimeInterval(-120), now: now).hasPrefix("reset "))
    }

    func testTokenFormatting() {
        XCTAssertEqual(UsageFormatting.tokens(950), "950")
        XCTAssertEqual(UsageFormatting.tokens(1_500), "1.5K")
        XCTAssertEqual(UsageFormatting.tokens(184_200), "184K")
        XCTAssertEqual(UsageFormatting.tokens(2_500_000), "2.50M")
    }
}
