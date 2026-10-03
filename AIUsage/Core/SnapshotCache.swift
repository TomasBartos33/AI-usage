import Foundation

/// Persists the last known normalized snapshots so the app can show
/// last-known (and clearly stale) values right after launch.
/// Only normalized metrics are stored, never transcripts or prompts.
struct SnapshotCache: Sendable {
    let fileURL: URL

    static var `default`: SnapshotCache {
        SnapshotCache(fileURL: AppPaths.applicationSupport.appendingPathComponent("snapshots.json"))
    }

    func load() -> [ProviderID: UsageSnapshot] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.iso.decode([UsageSnapshot].self, from: data) else { return [:] }
        return Dictionary(decoded.map { ($0.provider, $0) }, uniquingKeysWith: { a, b in
            a.refreshedAt > b.refreshedAt ? a : b
        })
    }

    func save(_ snapshots: [ProviderID: UsageSnapshot]) {
        let list = snapshots.values.sorted { $0.provider.rawValue < $1.provider.rawValue }
        guard let data = try? JSONEncoder.iso.encode(list) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum AppPaths {
    /// `AI_USAGE_HOME` redirects every path (used to test missing-provider states).
    private static var homeOverride: URL? {
        guard let path = ProcessInfo.processInfo.environment["AI_USAGE_HOME"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var applicationSupport: URL {
        let base = homeOverride.map { $0.appendingPathComponent("Library/Application Support") }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AI-usage", isDirectory: true)
    }

    static var home: URL { homeOverride ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true) }
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
