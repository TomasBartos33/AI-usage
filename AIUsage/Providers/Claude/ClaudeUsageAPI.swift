import Foundation

/// Opt-in: reads current Claude plan utilization from Anthropic's usage
/// endpoint — the same metadata request Claude Code makes for `/usage`. It
/// returns counters only; it is not a Messages API call and uses no tokens.
///
/// It reuses Claude Code's existing sign-in: the OAuth access token is read
/// via `/usr/bin/security` (as Claude Code does), held in memory for the one
/// request, and never logged. When the access token has expired, it is
/// refreshed the way Claude Code refreshes it, and the rotated tokens are
/// written back to the same Keychain item, so Claude Code stays signed in.
/// This matters when Claude Code only runs inside the Claude desktop app,
/// which passes its own token to Claude Code and never renews the Keychain item.
struct ClaudeUsageAPI: Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    /// Claude Code's public OAuth client.
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let keychainService = "Claude Code-credentials"

    enum APIError: Error, LocalizedError, Equatable {
        case noCredentials, tokenExpired, refreshFailed, unauthorized, rateLimited, http(Int), malformedResponse

        var errorDescription: String? {
            switch self {
            case .noCredentials: return "No Claude Code sign-in found."
            case .tokenExpired: return "Claude Code's sign-in expired; sign in to Claude Code again."
            case .refreshFailed: return "Could not renew Claude Code's sign-in token; trying again later."
            case .unauthorized: return "Anthropic rejected Claude Code's sign-in token."
            case .rateLimited: return "Anthropic's usage endpoint is rate limiting; showing the last known value."
            case .http(let code): return "Anthropic's usage endpoint returned HTTP \(code)."
            case .malformedResponse: return "Unexpected response from Anthropic's usage endpoint."
            }
        }
    }

    func fetchWindows() async throws -> [UsageWindow] {
        let token = try await Self.validAccessToken()
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw APIError.unauthorized
        case 429: throw APIError.rateLimited
        case let code: throw APIError.http(code)
        }
        guard let json = LooseJSON.object(data) else { throw APIError.malformedResponse }
        return ClaudeParsers.windows(fromUtilization: json)
    }

    /// Extracts the access token from the Keychain item's JSON. Pure, for tests.
    static func accessToken(fromCredentials data: Data, now: Date = Date()) throws -> String {
        guard let oauth = LooseJSON.object(data).flatMap({ LooseJSON.dict($0["claudeAiOauth"]) }),
              let token = LooseJSON.string(oauth["accessToken"]) else { throw APIError.noCredentials }
        if let expiresAt = LooseJSON.date(oauth["expiresAt"]), expiresAt <= now.addingTimeInterval(30) {
            throw APIError.tokenExpired
        }
        return token
    }

    /// Body of the refresh request for the Keychain item's JSON, or nil when it
    /// has no usable refresh token. Pure, for tests.
    static func refreshRequestBody(fromCredentials data: Data, now: Date = Date()) -> [String: Any]? {
        guard let oauth = LooseJSON.object(data).flatMap({ LooseJSON.dict($0["claudeAiOauth"]) }),
              let refreshToken = LooseJSON.string(oauth["refreshToken"]) else { return nil }
        if let expiresAt = LooseJSON.date(oauth["refreshTokenExpiresAt"]), expiresAt <= now { return nil }
        var body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID]
        if let scopes = oauth["scopes"] as? [String], !scopes.isEmpty {
            body["scope"] = scopes.joined(separator: " ")
        }
        return body
    }

    /// The Keychain item's JSON with the tokens from a refresh response merged
    /// in, keeping every other field as Claude Code wrote it. Pure, for tests.
    static func refreshedCredentials(_ data: Data, response: [String: Any], now: Date = Date()) -> Data? {
        guard var root = LooseJSON.object(data),
              var oauth = LooseJSON.dict(root["claudeAiOauth"]),
              let accessToken = LooseJSON.string(response["access_token"]),
              let expiresIn = LooseJSON.double(response["expires_in"]) else { return nil }
        let nowMs = (now.timeIntervalSince1970 * 1000).rounded()
        oauth["accessToken"] = accessToken
        oauth["expiresAt"] = Int64(nowMs + expiresIn * 1000)
        if let refreshToken = LooseJSON.string(response["refresh_token"]) {
            oauth["refreshToken"] = refreshToken
        }
        if let refreshExpiresIn = LooseJSON.double(response["refresh_token_expires_in"]) {
            oauth["refreshTokenExpiresAt"] = Int64(nowMs + refreshExpiresIn * 1000)
        }
        if let scope = LooseJSON.string(response["scope"]) {
            oauth["scopes"] = scope.split(separator: " ").map(String.init)
        }
        root["claudeAiOauth"] = oauth
        return try? JSONSerialization.data(withJSONObject: root, options: .withoutEscapingSlashes)
    }

    private static func validAccessToken() async throws -> String {
        let credentials = try await readKeychain()
        do {
            return try accessToken(fromCredentials: credentials)
        } catch APIError.tokenExpired {
            return try await refresh(credentials)
        }
    }

    private static func refresh(_ credentials: Data) async throws -> String {
        guard let body = refreshRequestBody(fromCredentials: credentials) else { throw APIError.tokenExpired }
        var request = URLRequest(url: tokenEndpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 400, 401, 403: throw APIError.tokenExpired
        default: throw APIError.refreshFailed
        }
        guard let json = LooseJSON.object(data),
              let updated = refreshedCredentials(credentials, response: json) else { throw APIError.refreshFailed }

        // Claude Code may have renewed the item meanwhile; its tokens win.
        if let current = try? await readKeychain(), current != credentials,
           let token = try? accessToken(fromCredentials: current) {
            return token
        }
        try await writeKeychain(updated)
        return try accessToken(fromCredentials: updated)
    }

    private static func readKeychain() async throws -> Data {
        let output = try await runSecurity(arguments: ["find-generic-password", "-s", keychainService, "-w"])
        guard !output.isEmpty else { throw APIError.noCredentials }
        return output
    }

    /// Writes like Claude Code: `security -i` with the payload hex-encoded on
    /// stdin, so the tokens never appear in a process argument list.
    private static func writeKeychain(_ credentials: Data) async throws {
        let hex = credentials.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -a \"\(NSUserName())\" -s \"\(keychainService)\" -X \"\(hex)\"\n"
        _ = try await runSecurity(arguments: ["-i"], input: Data(command.utf8))
        guard (try? await readKeychain()) == credentials else { throw APIError.refreshFailed }
    }

    private static func runSecurity(arguments: [String], input: Data? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                process.arguments = arguments
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice
                let stdin = Pipe()
                if input != nil { process.standardInput = stdin }
                guard (try? process.run()) != nil else {
                    continuation.resume(throwing: APIError.noCredentials)
                    return
                }
                if let input {
                    stdin.fileHandleForWriting.write(input)
                    try? stdin.fileHandleForWriting.close()
                }
                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    // `find-generic-password -w` ends its output with a newline.
                    continuation.resume(returning: output.last == 0x0A ? output.dropLast() : output)
                } else {
                    continuation.resume(throwing: APIError.noCredentials)
                }
            }
        }
    }
}
