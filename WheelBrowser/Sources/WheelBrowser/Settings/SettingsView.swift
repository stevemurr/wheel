import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            AppearanceSection()
            TabDockSettingsSection()
            LLMSettingsSection()
            SemanticSearchSettingsSection()
            WidgetSettingsSection()

            Section("MCP Server") {
                MCPSettingsView()
            }

            DebugSection()
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 900)
    }
}

#Preview {
    SettingsView()
}
