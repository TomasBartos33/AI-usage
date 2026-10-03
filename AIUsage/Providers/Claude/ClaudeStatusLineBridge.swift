import Foundation

/// Optional integration with Claude Code's status line.
///
/// Claude Code runs the configured status line command after each assistant
/// message and passes session metadata (model, context window, cost and the
/// account's `rate_limits`) on stdin. This is a local hook: it never triggers
/// a model request. The bridge script keeps an allowlisted subset of that JSON
/// (no session titles, transcript paths or other text) for AI-usage, then runs
/// the user's previous status line command so their status line keeps working.
struct ClaudeStatusLineBridge {
    /// AI-usage's Application Support directory (overridable for tests).
    var supportDirectory = AppPaths.applicationSupport
    /// Claude Code user settings file.
    var settingsFile = ClaudePaths.userSettingsFile

    var scriptURL: URL { supportDirectory.appendingPathComponent("bin/claude-statusline-bridge.sh") }
    /// Must match the directory hard-coded in `script`.
    var bridgeDirectory: URL { supportDirectory.appendingPathComponent("claude", isDirectory: true) }
    var snapshotFile: URL { bridgeDirectory.appendingPathComponent("statusline.json") }
    private var previousCommandFile: URL { bridgeDirectory.appendingPathComponent("previous-command") }
    private var previousConfigFile: URL { bridgeDirectory.appendingPathComponent("previous-statusline.json") }

    enum State: Equatable {
        case notInstalled
        case installed(chainsPreviousCommand: Bool)
        /// Another status line is configured; installing will chain it.
        case otherStatusLine(command: String)
    }

    var isInstalled: Bool {
        if case .installed = state() { return true }
        return false
    }

    func state() -> State {
        let settings = readSettings(settingsFile) ?? [:]
        guard let statusLine = settings["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else { return .notInstalled }
        if command.contains(scriptURL.lastPathComponent) {
            return .installed(chainsPreviousCommand: FileManager.default.fileExists(atPath: previousCommandFile.path))
        }
        return .otherStatusLine(command: command)
    }

    /// Installs the script and points Claude Code's user settings at it.
    /// The previous status line configuration is saved for `uninstall()`.
    func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: bridgeDirectory, withIntermediateDirectories: true)
        try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var settings = readSettings(settingsFile) ?? [:]
        if fm.fileExists(atPath: settingsFile.path) {
            let backup = settingsFile.appendingPathExtension("ai-usage-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsFile, to: backup)
        }

        var newStatusLine: [String: Any] = ["type": "command"]
        if let existing = settings["statusLine"] as? [String: Any] {
            let existingCommand = existing["command"] as? String ?? ""
            if !existingCommand.contains(scriptURL.lastPathComponent) {
                let data = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted])
                try data.write(to: previousConfigFile, options: .atomic)
                if !existingCommand.isEmpty {
                    try existingCommand.write(to: previousCommandFile, atomically: true, encoding: .utf8)
                }
            }
            // Keep layout options such as padding / refreshInterval.
            for (key, value) in existing where key != "command" && key != "type" { newStatusLine[key] = value }
        }
        newStatusLine["command"] = "\"\(scriptURL.path)\""
        settings["statusLine"] = newStatusLine
        try writeSettings(settings, to: settingsFile)
    }

    /// Restores the previous status line (or removes ours) and deletes bridge files.
    func uninstall() throws {
        let fm = FileManager.default
        var settings = readSettings(settingsFile) ?? [:]
        if case .installed = state() {
            if let data = try? Data(contentsOf: previousConfigFile),
               let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings["statusLine"] = previous
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try writeSettings(settings, to: settingsFile)
        }
        for url in [previousConfigFile, previousCommandFile, snapshotFile, scriptURL] {
            try? fm.removeItem(at: url)
        }
    }

    private func readSettings(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func writeSettings(_ settings: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// POSIX sh, only macOS built-in tools. Keeps an allowlist of numeric /
    /// metadata fields; the raw input is deleted immediately after use.
    static let script = #"""
    #!/bin/sh
    # AI-usage bridge for the Claude Code status line.
    # Saves an allowlisted subset of the status line JSON (rate limits, model,
    # context window, cost, working directory) for the AI-usage menu bar app,
    # then runs your previous status line command, if one was configured.
    # This script never contacts any server and never invokes a model.
    dir="$HOME/Library/Application Support/AI-usage/claude"
    mkdir -p "$dir" 2>/dev/null
    raw="$dir/.input.$$"
    trap 'rm -f "$raw" "$raw.out"' EXIT
    cat > "$raw"
    # x: JSON object/number at a key path; s: JSON-escaped string at a key path.
    x() { /usr/bin/plutil -extract "$1" json -o - "$raw" 2>/dev/null || printf 'null'; }
    s() {
      v=$(/usr/bin/plutil -extract "$1" raw -o - "$raw" 2>/dev/null) || { printf 'null'; return; }
      printf '"%s"' "$(printf '%s' "$v" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037')"
    }
    printf '{"captured_at":%s,"session_id":%s,"version":%s,"model":%s,"cwd":%s,"context_window":%s,"cost":%s,"rate_limits":%s}\n' \
      "$(date +%s)" "$(s session_id)" "$(s version)" "$(x model)" "$(s workspace.current_dir)" \
      "$(x context_window)" "$(x cost)" "$(x rate_limits)" > "$raw.out" \
      && mv -f "$raw.out" "$dir/statusline.json"
    if [ -s "$dir/previous-command" ]; then
      /bin/sh -c "$(cat "$dir/previous-command")" < "$raw"
    fi
    """#
}
