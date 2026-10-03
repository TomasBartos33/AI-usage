import Foundation

/// Minimal JSON-RPC client for `codex app-server` over stdio.
///
/// Only account metadata methods are used (`account/read`,
/// `account/rateLimits/read`). These read the account's usage counters and do
/// not start threads or turns, so they never cause model inference.
///
/// Lifecycle: one short-lived process per query. It is started, asked the
/// questions, then its stdin is closed (which makes app-server exit). A
/// watchdog terminates it if it does not answer or exit in time, so no
/// process can linger.
struct CodexAppServerClient: Sendable {
    let executable: URL
    var timeout: TimeInterval = 15

    /// JSON payloads are only read on the requesting task, never shared.
    struct Result: @unchecked Sendable {
        var rateLimits: [String: Any]?
        var account: [String: Any]?
        var rateLimitsError: String?
    }

    enum ClientError: Error, LocalizedError {
        case launchFailed(String)
        case timedOut
        case noResponse

        var errorDescription: String? {
            switch self {
            case .launchFailed(let reason): return "Could not start codex app-server: \(reason)"
            case .timedOut: return "codex app-server did not respond in time"
            case .noResponse: return "codex app-server exited without answering"
            }
        }
    }

    /// Methods this client is allowed to call. Anything that could start a
    /// turn (and therefore inference) is intentionally impossible to send.
    static let allowedMethods: Set<String> = ["initialize", "initialized", "account/read", "account/rateLimits/read"]

    func fetch() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Swift.Result { try run() })
            }
        }
    }

    private func run() throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = CodexLocator.searchPath(existing: environment["PATH"])
        environment["RUST_LOG"] = "error"
        process.environment = environment

        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ClientError.launchFailed(error.localizedDescription)
        }

        // Watchdog: guarantees the subprocess never outlives the request.
        let timedOut = TimeoutFlag()
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer {
            watchdog.cancel()
            try? stdin.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        let writer = stdin.fileHandleForWriting
        func send(_ message: [String: Any]) {
            guard let method = message["method"] as? String, Self.allowedMethods.contains(method),
                  var data = try? JSONSerialization.data(withJSONObject: message) else { return }
            data.append(0x0A)
            try? writer.write(contentsOf: data)
        }

        send(["id": 1, "method": "initialize",
              "params": ["clientInfo": ["name": "ai-usage", "title": "AI-usage", "version": AppInfo.version]]])
        send(["method": "initialized"])
        send(["id": 2, "method": "account/rateLimits/read"])
        send(["id": 3, "method": "account/read", "params": ["refreshToken": false]])

        var result = Result()
        var answered = Set<Int>()
        var buffer = Data()
        let reader = stdout.fileHandleForReading

        readLoop: while answered.count < 3 {
            let chunk = reader.availableData
            if chunk.isEmpty { break } // EOF: process exited or was terminated
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let message = LooseJSON.object(Data(line)), let id = LooseJSON.int(message["id"]) else { continue }
                answered.insert(id)
                switch id {
                case 2:
                    if let payload = LooseJSON.dict(message["result"]) {
                        result.rateLimits = payload
                    } else if let error = LooseJSON.dict(message["error"]) {
                        result.rateLimitsError = LooseJSON.string(error["message"]) ?? "Request failed"
                    }
                case 3:
                    result.account = LooseJSON.dict(message["result"])
                default:
                    break
                }
                if answered.isSuperset(of: [1, 2, 3]) { break readLoop }
            }
        }

        // Closing stdin asks app-server to shut down; give it a moment to exit cleanly.
        try? writer.close()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { usleep(20_000) }

        if timedOut.isSet && answered.count < 3 { throw ClientError.timedOut }
        if result.rateLimits == nil && result.account == nil && result.rateLimitsError == nil {
            throw ClientError.noResponse
        }
        return result
    }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
