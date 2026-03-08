import SwiftUI

struct SemanticSearchSettingsSection: View {
    @ObservedObject private var settings = AppSettings.shared
    private var semanticSearch = SemanticSearchManagerV2.shared

    var body: some View {
        Section("Semantic Search") {
            Toggle("Enable Semantic Search", isOn: $settings.semanticSearchEnabled)
                .onChange(of: settings.semanticSearchEnabled) {
                    Task { await semanticSearch.reinitialize() }
                }

            Text("Index your browsing history for semantic search. Uses on-device embeddings to find pages by meaning, not just keywords. Supports @Web, @History, @ReadingList mentions.")
                .font(.caption)
                .foregroundColor(.secondary)

            if settings.semanticSearchEnabled {
                HStack {
                    if semanticSearch.isAvailable {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(
                            "Active — \(semanticSearch.stats.pageCount) pages / \(semanticSearch.stats.chunkCount) chunks indexed"
                        )
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let error = semanticSearch.lastError {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    } else {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Initializing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
