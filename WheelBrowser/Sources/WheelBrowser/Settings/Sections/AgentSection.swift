import SwiftUI

struct AgentSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section("Agent") {
            if settings.agentId.isEmpty {
                Text("No agent created yet")
                    .foregroundColor(.secondary)
            } else {
                HStack {
                    Text("Agent ID:")
                    Text(settings.agentId)
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }

                Button("Reset Agent", role: .destructive) {
                    settings.agentId = ""
                }
            }
        }
    }
}
