import XCTest
@testable import AIUsage

final class CodexParserTests: XCTestCase {
    private let observed = Date(timeIntervalSince1970: 1_791_000_000)

    func testAppServerRateLimits() throws {
        let json = """
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1791037284},
          "secondary":{"usedPercent":34,"windowDurationMins":10080,"resetsAt":1791624084},
          "credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"plus"},
         "rateLimitsByLimitId":{
          "codex":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1791037284},
            "secondary":{"usedPercent":34,"windowDurationMins":10080,"resetsAt":1791624084},"planType":"plus"},
          "base_model_inference":{"limitId":"base_model_inference","limitName":"gpt-reserve",
            "primary":{"usedPercent":5,"windowDurationMins":10080,"resetsAt":1791624858},"secondary":null}}}
        """
        let result = try XCTUnwrap(CodexParsers.rateLimitsResponse(XCTUnwrap(LooseJSON.object(Data(json.utf8))), observedAt: observed))
        XCTAssertEqual(result.plan, "Plus")
        XCTAssertNil(result.creditsBalance)
        XCTAssertEqual(result.windows.count, 3)

        let session = try XCTUnwrap(result.windows.first { $0.kind == .session })
        XCTAssertEqual(session.usedPercent, 12)
        XCTAssertEqual(session.durationMinutes, 300)
        XCTAssertEqual(session.shortName, "5h")
        XCTAssertEqual(session.resetsAt, Date(timeIntervalSince1970: 1_791_037_284))

        let weekly = try XCTUnwrap(result.windows.first { $0.kind == .weekly })
        XCTAssertEqual(weekly.usedPercent, 34)
        XCTAssertEqual(weekly.id, "secondary")

        let extra = try XCTUnwrap(result.windows.first { $0.kind == .other })
        XCTAssertEqual(extra.name, "gpt-reserve (weekly)")
    }

    func testOnlyOneWindow() throws {
        let json = #"{"rateLimits":{"primary":{"usedPercent":50,"windowDurationMins":300},"secondary":null}}"#
        let result = try XCTUnwrap(CodexParsers.rateLimitsResponse(XCTUnwrap(LooseJSON.object(Data(json.utf8))), observedAt: observed))
        XCTAssertEqual(result.windows.map(\.kind), [.session])
        XCTAssertNil(result.windows[0].resetsAt)
    }

    func testMalformedRateLimitsAreIgnored() {
        let json = #"{"rateLimits":{"primary":{"usedPercent":"lots"},"secondary":[1,2]}}"#
        let result = CodexParsers.rateLimitsResponse(LooseJSON.object(Data(json.utf8))!, observedAt: observed)
        XCTAssertEqual(result?.windows, [])
    }

    func testAccountState() {
        XCTAssertEqual(CodexParsers.accountState(["account": NSNull(), "requiresOpenaiAuth": true]), .signedOut)
        XCTAssertEqual(CodexParsers.accountState(["account": ["type": "chatgpt", "email": "x@y", "planType": "pro"]]),
                       .signedIn(plan: "Pro"))
        XCTAssertEqual(CodexParsers.accountState(["account": ["type": "apiKey"]]), .apiKey)
    }

    func testSessionLogSummary() {
        let lines = [
            #"{"timestamp":"2026-10-03T09:21:18.000Z","type":"session_meta","payload":{"id":"x","cwd":"/old"}}"#,
            #"{"timestamp":"2026-10-03T09:21:19.000Z","type":"turn_context","payload":{"cwd":"/Users/me/project","model":"gpt-5.6-terra","effort":"medium"}}"#,
            #"{"timestamp":"2026-10-03T09:21:20.000Z","type":"response_item","payload":{"type":"message","content":[{"type":"input_text","text":"secret prompt mentioning token_count"}]}}"#,
            "not json at all",
            #"{"timestamp":"2026-10-03T09:21:24.558Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":19700,"cached_input_tokens":11008,"output_tokens":14,"total_tokens":19714},"last_token_usage":{"input_tokens":19700,"output_tokens":14,"total_tokens":19714},"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":{"used_percent":7.0,"window_minutes":300,"resets_at":1791037283},"secondary":{"used_percent":2.5,"window_minutes":10080,"resets_at":1791624083},"plan_type":"plus"}}}"#,
            #"{"timestamp":"2026-10-03T09:21:25.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#,
        ]
        let summary = CodexParsers.summarizeSessionLog(lines: lines)
        XCTAssertEqual(summary.session.model, "gpt-5.6-terra")
        XCTAssertEqual(summary.session.workingDirectory, "/Users/me/project")
        XCTAssertEqual(summary.session.inputTokens, 19700)
        XCTAssertEqual(summary.session.outputTokens, 14)
        XCTAssertEqual(summary.session.contextWindowTokens, 258400)
        XCTAssertEqual(summary.session.contextUsedPercent!, 7.63, accuracy: 0.01)
        XCTAssertEqual(summary.windows.map(\.usedPercent), [7.0, 2.5])
        XCTAssertEqual(summary.plan, "Plus")
        XCTAssertEqual(summary.rateLimitsObservedAt, LooseJSON.parseISO8601("2026-10-03T09:21:24.558Z"))
        // Last activity is the newest event that was inspected.
        XCTAssertEqual(summary.session.lastActivity, LooseJSON.parseISO8601("2026-10-03T09:21:24.558Z"))
    }

    func testLegacyRelativeReset() {
        let line = #"{"timestamp":"2026-01-01T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":40,"window_minutes":300,"resets_in_seconds":600}}}}"#
        let summary = CodexParsers.summarizeSessionLog(lines: [line])
        XCTAssertEqual(summary.windows.first?.resetsAt, LooseJSON.parseISO8601("2026-01-01T00:10:00Z"))
    }

    func testEmptyLog() {
        let summary = CodexParsers.summarizeSessionLog(lines: [String]())
        XCTAssertTrue(summary.windows.isEmpty)
        XCTAssertTrue(summary.session.isEmpty)
    }

    func testLatestRolloutFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("2026/09/30"), new = root.appendingPathComponent("2026/10/03")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        let a = old.appendingPathComponent("rollout-a.jsonl"), b = new.appendingPathComponent("rollout-b.jsonl")
        try Data("{}".utf8).write(to: a)
        try Data("{}".utf8).write(to: b)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: a.path)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: b.path)
        // A resumed older session written more recently wins over the newer directory.
        XCTAssertEqual(CodexLocator.latestRolloutFile(in: root)?.lastPathComponent, "rollout-a.jsonl")
        XCTAssertNil(CodexLocator.latestRolloutFile(in: root.appendingPathComponent("missing")))
    }

    func testFileTailDropsPartialFirstLine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("aaaaaaaaaa\nbbbb\ncccc\n".utf8).write(to: url)
        XCTAssertEqual(FileTail.lines(of: url, maxBytes: 12)?.map(String.init), ["bbbb", "cccc"])
        XCTAssertEqual(FileTail.lines(of: url, maxBytes: 9)?.map(String.init), ["cccc"])
        XCTAssertEqual(FileTail.lines(of: url, maxBytes: 7)?.map(String.init), ["cccc"])
        XCTAssertEqual(FileTail.lines(of: url, maxBytes: 1000)?.map(String.init), ["aaaaaaaaaa", "bbbb", "cccc"])
    }

    func testAppServerClientRefusesInferenceMethods() {
        XCTAssertFalse(CodexAppServerClient.allowedMethods.contains("turn/start"))
        XCTAssertFalse(CodexAppServerClient.allowedMethods.contains("thread/start"))
        XCTAssertFalse(CodexAppServerClient.allowedMethods.contains { $0.hasPrefix("turn/") || $0.hasPrefix("thread/") || $0.hasPrefix("review/") })
    }

    func testDateParsing() {
        XCTAssertEqual(LooseJSON.date(1_791_037_284), Date(timeIntervalSince1970: 1_791_037_284))
        XCTAssertEqual(LooseJSON.date(1_791_019_545_803), Date(timeIntervalSince1970: 1_791_019_545.803))
        XCTAssertNotNil(LooseJSON.date("2026-10-03T13:59:59.659249+00:00"))
        XCTAssertNil(LooseJSON.date(true))
        XCTAssertNil(LooseJSON.date("garbage"))
    }
}
