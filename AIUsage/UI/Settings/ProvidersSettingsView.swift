import SwiftUI

/// Data sources, capability matrix and provider-specific options.
struct ProvidersSettingsView: View {
    let store: UsageStore
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            capabilitySection
            CodexSettingsSection(store: store, preferences: preferences)
            ClaudeSettingsSection(store: store, preferences: preferences)
        }
        .formStyle(.grouped)
    }

    private var capabilitySection: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Metric").fontWeight(.semibold)
                    ForEach(ProviderID.builtIn, id: \.self) { id in
                        Text(ProviderBranding.of(id).shortName).fontWeight(.semibold)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Metric.allCases, id: \.self) { metric in
                    GridRow {
                        Text(metric.displayName)
                        ForEach(ProviderID.builtIn, id: \.self) { id in
                            let supported = store.capabilities(of: id).supports(metric)
                            Image(systemName: supported ? "checkmark" : "minus")
                                .foregroundStyle(supported ? .primary : .tertiary)
                                .accessibilityLabel(supported ? "Supported" : "Not supported")
                        }
                    }
                }
            }
        } header: {
            Text("Capabilities")
        } footer: {
            Text("AI-usage only reads local files and account metadata. It never sends prompts or makes model requests to obtain usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProviderStatusRows: View {
    let snapshot: UsageSnapshot?
    let now: Date

    var body: some View {
        LabeledContent("Status", value: snapshot?.status.summary ?? "Unknown")
        if let snapshot, let source = snapshot.rateLimitsSource, let observed = snapshot.rateLimitsObservedAt {
            LabeledContent("Rate limits", value: "\(source.displayName), \(UsageFormatting.relativePast(observed, now: now))")
        }
        if let source = snapshot?.sessionSource {
            LabeledContent("Session data", value: source.displayName)
        }
    }
}

private struct CodexSettingsSection: View {
    let store: UsageStore
    @Bindable var preferences: Preferences
    @State private var pathDraft = ""

    var body: some View {
        Section {
            ProviderStatusRows(snapshot: store.snapshots[.codex], now: store.now)
            LabeledContent("Codex CLI") {
                Text(CodexLocator.executable(override: preferences.codexExecutablePath)?.path ?? "Not found")
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TextField("Custom CLI path", text: $pathDraft, prompt: Text("Detected automatically"))
                .onSubmit(apply)
                .onAppear { pathDraft = preferences.codexExecutablePath }
            if pathDraft != preferences.codexExecutablePath {
                Button("Apply", action: apply)
            }
        } header: {
            Text("Codex")
        } footer: {
            Text("Rate limits come from Codex session logs and from `codex app-server` account metadata (account/rateLimits/read). Neither starts a conversation or uses tokens.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func apply() {
        preferences.codexExecutablePath = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        store.configureProviders()
    }
}

private struct ClaudeSettingsSection: View {
    let store: UsageStore
    @Bindable var preferences: Preferences
    @State private var bridgeState = ClaudeStatusLineBridge().state()
    @State private var confirmingInstall = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            ProviderStatusRows(snapshot: store.snapshots[.claude], now: store.now)
            Toggle("Fetch live usage from Anthropic", isOn: $preferences.claudeLiveUsage)
                .onChange(of: preferences.claudeLiveUsage) { _, _ in store.configureProviders() }
            Text("Asks Anthropic's usage endpoint (the one behind Claude Code's /usage) using Claude Code's sign-in. Counters only, no tokens used; the sign-in token is read from the Keychain for each request. An expired token is renewed as Claude Code does it and written back to Claude Code's Keychain item.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Status line bridge") {
                Text(bridgeDescription)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Spacer()
                switch bridgeState {
                case .installed:
                    Button("Remove Bridge", role: .destructive) { perform { try ClaudeStatusLineBridge().uninstall() } }
                case .notInstalled, .otherStatusLine:
                    Button("Install Bridge…") { confirmingInstall = true }
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Claude Code")
        } footer: {
            Text("Rate limits come from the usage cache Claude Code keeps in ~/.claude.json; session details come from local transcripts. The optional status line bridge adds the rate limits, context window and cost Claude Code reports after each reply, so values stay current while you work.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Install the Claude Code status line bridge?", isPresented: $confirmingInstall) {
            Button("Install") { perform { try ClaudeStatusLineBridge().install() } }
        } message: {
            Text(installMessage)
        }
    }

    private var bridgeDescription: String {
        switch bridgeState {
        case .notInstalled: return "Not installed"
        case .installed(let chains): return chains ? "Installed (runs your previous status line too)" : "Installed"
        case .otherStatusLine: return "Not installed (custom status line in use)"
        }
    }

    private var installMessage: String {
        var text = "AI-usage will set the statusLine command in ~/.claude/settings.json (a backup is saved next to it). Claude Code runs it locally after each reply; it makes no network or model requests."
        if case .otherStatusLine = bridgeState {
            text += " Your current status line command will keep running and is restored if you remove the bridge."
        }
        return text
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        bridgeState = ClaudeStatusLineBridge().state()
        store.configureProviders()
    }
}
