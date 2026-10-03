import Foundation

/// Locations of Claude Code's local data.
enum ClaudePaths {
    private static var configDirOverride: URL? {
        guard let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty else { return nil }
        return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// `~/.claude` (settings, transcripts).
    static var configDirectory: URL {
        configDirOverride ?? AppPaths.home.appendingPathComponent(".claude", isDirectory: true)
    }

    /// Global state file. Claude Code caches the account's usage utilization here.
    static var globalStateFile: URL {
        if let override = configDirOverride { return override.appendingPathComponent(".claude.json") }
        return AppPaths.home.appendingPathComponent(".claude.json")
    }

    static var projectsDirectory: URL { configDirectory.appendingPathComponent("projects", isDirectory: true) }
    static var userSettingsFile: URL { configDirectory.appendingPathComponent("settings.json") }

    /// Where the optional status line bridge stores its sanitized snapshot.
    static var bridgeDirectory: URL { AppPaths.applicationSupport.appendingPathComponent("claude", isDirectory: true) }
    static var bridgeSnapshotFile: URL { bridgeDirectory.appendingPathComponent("statusline.json") }

    static func executable() -> URL? {
        let home = AppPaths.home.path
        return [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
        ]
        .map { URL(fileURLWithPath: $0) }
        .first { FileManager.default.isExecutableFile(atPath: $0.resolvingSymlinksInPath().path) }
    }

    static var isInstalled: Bool {
        executable() != nil || FileManager.default.fileExists(atPath: configDirectory.path)
    }

    /// Newest transcript (`projects/<project>/<session>.jsonl`) by modification date.
    static func latestTranscript(in projects: URL = projectsDirectory) -> URL? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        let projectDirs = (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        var best: (url: URL, date: Date)?
        for dir in projectDirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            for file in files where isTranscript(file) {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if best == nil || date > best!.date { best = (file, date) }
            }
        }
        return best?.url
    }

    static func isTranscript(_ url: URL) -> Bool {
        url.pathExtension == "jsonl" && url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "projects"
    }
}
