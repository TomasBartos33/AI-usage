import SwiftUI

/// Shows which metrics each provider supports and where data comes from.
struct ProvidersSettingsView: View {
    let store: UsageStore
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("Metric").fontWeight(.semibold)
                        ForEach(store.orderedProviderIDs, id: \.self) { id in
                            Text(ProviderBranding.of(id).shortName).fontWeight(.semibold)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(Metric.allCases, id: \.self) { metric in
                        GridRow {
                            Text(metric.displayName)
                            ForEach(store.orderedProviderIDs, id: \.self) { id in
                                Image(systemName: store.capabilities(of: id).supports(metric) ? "checkmark" : "minus")
                                    .foregroundStyle(store.capabilities(of: id).supports(metric) ? .primary : .tertiary)
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

            ForEach(store.orderedProviderIDs, id: \.self) { id in
                Section(ProviderBranding.of(id).displayName) {
                    LabeledContent("Status", value: store.snapshots[id]?.status.summary ?? "Unknown")
                    if let source = store.snapshots[id]?.rateLimitsSource {
                        LabeledContent("Rate limits from", value: source.displayName)
                    }
                    if let source = store.snapshots[id]?.sessionSource {
                        LabeledContent("Session data from", value: source.displayName)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
