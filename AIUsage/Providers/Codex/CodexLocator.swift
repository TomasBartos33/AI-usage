import Foundation

/// Finds the Codex CLI and its data directory without relying on the shell's
/// PATH (GUI apps get a minimal environment).
enum CodexLocator {
    static var codexHome: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return AppPaths.home.appendingPathComponent(".codex", isDirectory: true)
    }

    static var sessionsDirectory: URL { codexHome.appendingPathComponent("sessions", isDirectory: true) }

    static func candidateExecutables(override: String?) -> [URL] {
        var paths: [String] = []
        if let override, !override.isEmpty { paths.append((override as NSString).expandingTildeInPath) }
        let home = AppPaths.home.path
        paths += [
            "\(home)/.local/bin/codex",
            "\(codexHome.path)/packages/standalone/current/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.volta/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        ]
        return paths.map { URL(fileURLWithPath: $0) }
    }

    static func executable(override: String?) -> URL? {
        candidateExecutables(override: override).first {
            FileManager.default.isExecutableFile(atPath: $0.resolvingSymlinksInPath().path)
        }
    }

    /// PATH used for the app-server subprocess, in case the CLI is a script wrapper (e.g. npm installs).
    static func searchPath(existing: String?) -> String {
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(AppPaths.home.path)/.local/bin", "/usr/bin", "/bin"]
        let current = (existing ?? "").split(separator: ":").map(String.init)
        return (current + extra.filter { !current.contains($0) }).joined(separator: ":")
    }

    /// Most recently modified rollout file. Rollouts live in `sessions/YYYY/MM/DD/`;
    /// resumed sessions append to their original file, so we compare modification
    /// dates across the newest few day directories rather than trusting names.
    static func latestRolloutFile(in sessions: URL = sessionsDirectory, dayDirectoriesToScan: Int = 7) -> URL? {
        let fm = FileManager.default
        func sortedSubdirectories(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                .filter { $0.hasDirectoryPath || (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var dayDirectories: [URL] = []
        outer: for year in sortedSubdirectories(sessions) {
            for month in sortedSubdirectories(year) {
                for day in sortedSubdirectories(month) {
                    dayDirectories.append(day)
                    if dayDirectories.count >= dayDirectoriesToScan { break outer }
                }
            }
        }
        var best: (url: URL, date: Date)?
        for directory in dayDirectories {
            let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [.skipsHiddenFiles])) ?? []
            for file in files where isRolloutFile(file) {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if best == nil || date > best!.date { best = (file, date) }
            }
        }
        return best?.url
    }

    static func isRolloutFile(_ url: URL) -> Bool {
        url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-")
    }
}
