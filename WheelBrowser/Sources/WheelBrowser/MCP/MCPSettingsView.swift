import SwiftUI

/// Settings view for the MCP Server configuration
struct MCPSettingsView: View {
    @ObservedObject private var mcpServer = MCPServer.shared
    @State private var portInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Server toggle
            HStack {
                Toggle("Enable MCP Server", isOn: Binding(
                    get: { mcpServer.isRunning },
                    set: { newValue in
                        if newValue {
                            mcpServer.start()
                        } else {
                            mcpServer.stop()
                        }
                    }
                ))

                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(mcpServer.isRunning ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(mcpServer.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("Enables external tools (like Claude Desktop) to control the browser via MCP protocol.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Port configuration
            HStack {
                Text("Port")
                Spacer()
                TextField("", text: $portInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .disabled(mcpServer.isRunning)
                    .onAppear {
                        portInput = String(mcpServer.port)
                    }
                    .onChange(of: portInput) { _, newValue in
                        if let port = UInt16(newValue) {
                            mcpServer.port = port
                        }
                    }
            }

            // Connection info
            if mcpServer.isRunning {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.secondary)
                    Text("http://localhost:\(mcpServer.port)/mcp")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                if mcpServer.connectionCount > 0 {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.green)
                        Text("\(mcpServer.connectionCount) active connection\(mcpServer.connectionCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Error display
            if let error = mcpServer.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            Divider()

            // Available tools info
            DisclosureGroup("Available Tools") {
                VStack(alignment: .leading, spacing: 8) {
                    ToolInfoRow(
                        name: "browser_snapshot",
                        description: "Get interactive elements on the page"
                    )
                    ToolInfoRow(
                        name: "browser_click",
                        description: "Click an element by ID"
                    )
                    ToolInfoRow(
                        name: "browser_type",
                        description: "Type text into an element"
                    )
                    ToolInfoRow(
                        name: "browser_scroll",
                        description: "Scroll the page"
                    )
                    ToolInfoRow(
                        name: "browser_navigate",
                        description: "Navigate to a URL"
                    )
                    ToolInfoRow(
                        name: "agent_run",
                        description: "Run an autonomous agent task"
                    )
                }
                .padding(.top, 4)
            }

            // Test commands
            DisclosureGroup("Test Commands") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("List tools:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("""
                    curl -X POST http://localhost:\(mcpServer.port)/mcp \\
                      -H "Content-Type: application/json" \\
                      -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
                    """)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text("Get snapshot:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("""
                    curl -X POST http://localhost:\(mcpServer.port)/mcp \\
                      -H "Content-Type: application/json" \\
                      -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}'
                    """)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Tool Info Row

private struct ToolInfoRow: View {
    let name: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 120, alignment: .leading)

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    MCPSettingsView()
        .frame(width: 400)
        .padding()
}
