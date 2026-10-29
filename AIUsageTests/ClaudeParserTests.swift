import XCTest
@testable import AIUsage

final class ClaudeParserTests: XCTestCase {
    func testUsageCache() throws {
        let json = """
        {"oauthAccount":{"emailAddress":"someone@example.com","organizationType":"claude_pro"},
         "cachedUsageUtilization":{"fetchedAtMs":1791019545803,"accountUuid":"x","utilization":{
           "five_hour":{"utilization":23,"resets_at":"2026-10-03T13:59:59.659249+00:00"},
           "seven_day":{"utilization":10,"resets_at":"2026-10-06T01:59:59.659268+00:00"},
           "seven_day_opus":null,
           "iguana_necktie":{"utilization":0,"resets_at":"2026-11-05T07:59:00+00:00"},
           "extra_usage":{"is_enabled":false}}}}
        """
        let state = try XCTUnwrap(LooseJSON.object(Data(json.utf8)))
        let cache = try XCTUnwrap(ClaudeParsers.usageCache(fromGlobalState: state))
        XCTAssertEqual(cache.fetchedAt, Date(timeIntervalSince1970: 1_791_019_545.803))
        XCTAssertEqual(cache.windows.map(\.id), ["five_hour", "seven_day"])
        XCTAssertEqual(cache.windows[0].usedPercent, 23)
        XCTAssertEqual(cache.windows[0].kind, .session)
        XCTAssertEqual(cache.windows[1].kind, .weekly)
        XCTAssertEqual(cache.windows[0].resetsAt?.timeIntervalSince1970 ?? 0,
                       LooseJSON.parseISO8601("2026-10-03T13:59:59.659Z")!.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(ClaudeParsers.accountState(fromGlobalState: state), .subscription(plan: "Pro"))
    }

    func testMissingCacheAndAccount() {
        XCTAssertNil(ClaudeParsers.usageCache(fromGlobalState: ["numStartups": 3]))
        XCTAssertNil(ClaudeParsers.usageCache(fromGlobalState: ["cachedUsageUtilization": "garbage"]))
        XCTAssertEqual(ClaudeParsers.accountState(fromGlobalState: [:]), .noOAuthAccount)
        XCTAssertEqual(ClaudeParsers.planDisplayName("claude_max"), "Max")
    }

    func testStatusLine() throws {
        let json = """
        {"captured_at":1791019000,"session_id":"abc","version":"2.1.274","model":{"id":"claude-opus-5-5","display_name":"Opus"},
         "cwd":"/Users/me/proj","context_window":{"used_percentage":8,"context_window_size":200000},
         "cost":{"total_cost_usd":0.01234},
         "rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}
        """
        let parsed = ClaudeParsers.statusLine(try XCTUnwrap(LooseJSON.object(Data(json.utf8))))
        XCTAssertEqual(parsed.sessionID, "abc")
        XCTAssertEqual(parsed.windows.map(\.usedPercent), [23.5, 41.2])
        XCTAssertEqual(parsed.windows.map(\.kind), [.session, .weekly])
        XCTAssertEqual(parsed.session.model, "claude-opus-5-5")
        XCTAssertEqual(parsed.session.contextUsedPercent, 8)
        XCTAssertEqual(parsed.session.contextWindowTokens, 200_000)
        XCTAssertEqual(parsed.session.costUSD, Decimal(string: "0.0123"))
        XCTAssertEqual(parsed.session.workingDirectory, "/Users/me/proj")
    }

    func testStatusLineWithoutRateLimits() {
        let parsed = ClaudeParsers.statusLine(["model": ["display_name": "Sonnet"], "rate_limits": NSNull()])
        XCTAssertTrue(parsed.windows.isEmpty)
        XCTAssertEqual(parsed.session.model, "Sonnet")
    }

    private func assistantLine(id: String, input: Int, output: Int, cacheRead: Int = 0, model: String = "claude-opus-5-5",
                               sidechain: Bool = false, time: String = "2026-10-03T09:35:25.015Z") -> String {
        #"{"type":"assistant","isSidechain":\#(sidechain),"timestamp":"\#(time)","cwd":"/p","message":{"id":"\#(id)","model":"\#(model)","content":[{"type":"text","text":"private words"}],"usage":{"input_tokens":\#(input),"cache_read_input_tokens":\#(cacheRead),"cache_creation_input_tokens":0,"output_tokens":\#(output)}}}"#
    }

    func testTranscriptEntryIgnoresOtherLines() {
        XCTAssertNil(ClaudeParsers.transcriptEntry(line: #"{"type":"user","message":{"content":"assistant usage"}}"#))
        XCTAssertNil(ClaudeParsers.transcriptEntry(line: "{broken"))
        let entry = ClaudeParsers.transcriptEntry(line: assistantLine(id: "m1", input: 10, output: 5, cacheRead: 100))
        XCTAssertEqual(entry?.contextTokens, 110)
        XCTAssertEqual(entry?.model, "claude-opus-5-5")
    }

    func testTranscriptAccumulatorIsIncrementalAndDeduplicates() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = [assistantLine(id: "m1", input: 10, output: 5, cacheRead: 100),
                     assistantLine(id: "m1", input: 10, output: 5, cacheRead: 100), // same response, second content block
                     #"{"type":"user","message":{"role":"user","content":"hi"}}"#].joined(separator: "\n") + "\n"
        try Data(first.utf8).write(to: url)

        var accumulator = TranscriptAccumulator()
        accumulator.update(from: url)
        XCTAssertEqual(accumulator.inputTokens, 110)
        XCTAssertEqual(accumulator.outputTokens, 5)

        // Append a complete line and a partial one.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        let sidechain = assistantLine(id: "m2", input: 1, output: 2, model: "claude-haiku", sidechain: true, time: "2026-10-03T09:40:00Z")
        try handle.write(contentsOf: Data((sidechain + "\n" + #"{"type":"assist"#).utf8))
        try handle.close()

        accumulator.update(from: url)
        XCTAssertEqual(accumulator.inputTokens, 111)
        XCTAssertEqual(accumulator.outputTokens, 7)
        // Sidechain (subagent) messages count toward totals but not the main session's model/context.
        let info = try XCTUnwrap(accumulator.sessionInfo)
        XCTAssertEqual(info.model, "claude-opus-5-5")
        XCTAssertEqual(info.contextTokens, 110)
        XCTAssertEqual(info.lastActivity, LooseJSON.parseISO8601("2026-10-03T09:40:00Z"))
    }

    func testBridgeScriptKeepsOnlyAllowlistedFields() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let script = home.appendingPathComponent("bridge.sh")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try ClaudeStatusLineBridge.script.write(to: script, atomically: true, encoding: .utf8)

        let input = #"{"session_id":"s1","session_name":"Secret plans","transcript_path":"/x.jsonl","model":{"id":"m"},"workspace":{"current_dir":"/proj \\\"q\\\""},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1}}}"#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let output = home.appendingPathComponent("Library/Application Support/AI-usage/claude/statusline.json")
        let text = try String(contentsOf: output, encoding: .utf8)
        XCTAssertFalse(text.contains("Secret plans"))
        XCTAssertFalse(text.contains("transcript_path"))
        let parsed = ClaudeParsers.statusLine(try XCTUnwrap(LooseJSON.object(Data(text.utf8))))
        XCTAssertEqual(parsed.windows.first?.usedPercent, 12)
        XCTAssertEqual(parsed.session.workingDirectory, #"/proj \"q\""#)
        XCTAssertEqual(parsed.sessionID, "s1")
        // Raw input must not be left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, ["statusline.json"])
    }

    func testBridgeInstallChainsAndRestoresPreviousStatusLine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"{"model":"sonnet","statusLine":{"type":"command","command":"~/bin/my-line.sh","padding":1}}"#
        try Data(original.utf8).write(to: settings)

        let bridge = ClaudeStatusLineBridge(supportDirectory: root.appendingPathComponent("support"), settingsFile: settings)
        XCTAssertEqual(bridge.state(), .otherStatusLine(command: "~/bin/my-line.sh"))

        try bridge.install()
        XCTAssertEqual(bridge.state(), .installed(chainsPreviousCommand: true))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: bridge.scriptURL.path))
        let installed = try XCTUnwrap(LooseJSON.object(Data(contentsOf: settings)))
        XCTAssertEqual(installed["model"] as? String, "sonnet")
        let statusLine = try XCTUnwrap(installed["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["padding"] as? Int, 1)
        XCTAssertTrue((statusLine["command"] as? String)?.contains("claude-statusline-bridge.sh") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.path + ".ai-usage-backup"))

        // Installing twice must not record the bridge itself as the previous command.
        try bridge.install()
        try bridge.uninstall()
        let restored = try XCTUnwrap(LooseJSON.object(Data(contentsOf: settings)))
        let restoredLine = try XCTUnwrap(restored["statusLine"] as? [String: Any])
        XCTAssertEqual(restoredLine["command"] as? String, "~/bin/my-line.sh")
        XCTAssertEqual(bridge.state(), .otherStatusLine(command: "~/bin/my-line.sh"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.scriptURL.path))
    }

    func testBridgeInstallWithoutPreviousStatusLine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("settings.json")
        let bridge = ClaudeStatusLineBridge(supportDirectory: root.appendingPathComponent("support"), settingsFile: settings)
        XCTAssertEqual(bridge.state(), .notInstalled)
        try bridge.install()
        XCTAssertEqual(bridge.state(), .installed(chainsPreviousCommand: false))
        try bridge.uninstall()
        let restored = try XCTUnwrap(LooseJSON.object(Data(contentsOf: settings)))
        XCTAssertNil(restored["statusLine"])
    }

    func testAccessTokenParsing() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = #"{"claudeAiOauth":{"accessToken":"abc","expiresAt":1800003600000}}"#
        XCTAssertEqual(try ClaudeUsageAPI.accessToken(fromCredentials: Data(valid.utf8), now: now), "abc")
        let expired = #"{"claudeAiOauth":{"accessToken":"abc","expiresAt":1799999000000}}"#
        XCTAssertThrowsError(try ClaudeUsageAPI.accessToken(fromCredentials: Data(expired.utf8), now: now)) {
            XCTAssertEqual($0 as? ClaudeUsageAPI.APIError, .tokenExpired)
        }
        XCTAssertThrowsError(try ClaudeUsageAPI.accessToken(fromCredentials: Data("{}".utf8), now: now))
    }

    func testTokenRefresh() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stored = #"{"claudeAiOauth":{"accessToken":"old","refreshToken":"r1","expiresAt":1799999000000,"refreshTokenExpiresAt":1801000000000,"scopes":["user:inference","user:profile"],"subscriptionType":"pro"}}"#
        let body = try XCTUnwrap(ClaudeUsageAPI.refreshRequestBody(fromCredentials: Data(stored.utf8), now: now))
        XCTAssertEqual(body["grant_type"] as? String, "refresh_token")
        XCTAssertEqual(body["refresh_token"] as? String, "r1")
        XCTAssertEqual(body["client_id"] as? String, ClaudeUsageAPI.clientID)
        XCTAssertEqual(body["scope"] as? String, "user:inference user:profile")

        let deadRefresh = #"{"claudeAiOauth":{"accessToken":"old","refreshToken":"r1","refreshTokenExpiresAt":1799999000000}}"#
        XCTAssertNil(ClaudeUsageAPI.refreshRequestBody(fromCredentials: Data(deadRefresh.utf8), now: now))
        XCTAssertNil(ClaudeUsageAPI.refreshRequestBody(fromCredentials: Data(#"{"claudeAiOauth":{"accessToken":"old"}}"#.utf8), now: now))

        let response: [String: Any] = ["access_token": "new", "refresh_token": "r2", "expires_in": 3600]
        let updated = try XCTUnwrap(ClaudeUsageAPI.refreshedCredentials(Data(stored.utf8), response: response, now: now))
        XCTAssertEqual(try ClaudeUsageAPI.accessToken(fromCredentials: updated, now: now), "new")
        let oauth = try XCTUnwrap(LooseJSON.object(updated).flatMap { LooseJSON.dict($0["claudeAiOauth"]) })
        XCTAssertEqual(LooseJSON.string(oauth["refreshToken"]), "r2")
        XCTAssertEqual(LooseJSON.double(oauth["expiresAt"]), 1_800_003_600_000)
        XCTAssertEqual(LooseJSON.double(oauth["refreshTokenExpiresAt"]), 1_801_000_000_000)
        XCTAssertEqual(LooseJSON.string(oauth["subscriptionType"]), "pro")
        XCTAssertEqual(oauth["scopes"] as? [String], ["user:inference", "user:profile"])
        XCTAssertNil(ClaudeUsageAPI.refreshedCredentials(Data(stored.utf8), response: ["expires_in": 3600], now: now))
    }

    func testUsageEndpointResponse() throws {
        let json = #"{"five_hour":{"utilization":75.0,"resets_at":"2026-10-03T14:00:00.312422+00:00"},"seven_day":{"utilization":16.0,"resets_at":"2026-10-06T02:00:00.312449+00:00"},"seven_day_opus":null}"#
        let windows = ClaudeParsers.windows(fromUtilization: try XCTUnwrap(LooseJSON.object(Data(json.utf8))))
        XCTAssertEqual(windows.map(\.usedPercent), [75, 16])
        XCTAssertEqual(windows.map(\.kind), [.session, .weekly])
    }
}
