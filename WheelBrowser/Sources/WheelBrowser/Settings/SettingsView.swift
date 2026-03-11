import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            AppearanceSection()
            TabDockSettingsSection()
            LLMSettingsSection()
            SettingsAssistantSection()
            SemanticSearchSettingsSection()
            ExtensionsSettingsSection()
            AdBlockingSettingsSection()

            Section("MCP Server") {
                MCPSettingsView()
            }

            DebugSection()
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 980)
    }
}

#Preview {
    SettingsView()
}
