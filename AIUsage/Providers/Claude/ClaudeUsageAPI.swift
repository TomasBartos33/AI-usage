import Foundation

/// Opt-in: reads current Claude plan utilization from Anthropic's usage
/// endpoint — the same metadata request Claude Code makes for `/usage`. It
/// returns counters only; it is not a Messages API call and uses no tokens.
///
/// It reuses Claude Code's existing sign-in: the OAuth access token is read
/// via `/usr/bin/security` (as Claude Code does), held in memory for the one
/// request, and never logged or stored. Expired tokens are not refreshed,
/// because refreshing would rotate Claude Code's own credentials.
struct ClaudeUsageAPI: Sendable {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"

    enum APIError: Error, LocalizedError, Equatable {
        case noCredentials, tokenExpired, unauthorized, rateLimited, http(Int), malformedResponse

        var errorDescription: String? {
            switch self {
            case .noCredentials: return "No Claude Code sign-in found."
            case .tokenExpired: return "Claude Code's sign-in token expired; it renews next time Claude Code runs."
            case .unauthorized: return "Anthropic rejected Claude Code's sign-in token."
            case .rateLimited: return "Anthropic's usage endpoint is rate limiting; showing the last known value."
            case .http(let code): return "Anthropic's usage endpoint returned HTTP \(code)."
            case .malformedResponse: return "Unexpected response from Anthropic's usage endpoint."
            }
        }
    }

    func fetchWindows() async throws -> [UsageWindow] {
        let token = try await Self.accessToken()
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

    private static func accessToken() async throws -> String {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else {
                    continuation.resume(throwing: APIError.noCredentials)
                    return
                }
                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0, !output.isEmpty {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: APIError.noCredentials)
                }
            }
        }
        return try accessToken(fromCredentials: data)
    }
}
