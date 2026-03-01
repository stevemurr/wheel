import Foundation

/// Parses and stores CLI arguments for headless browser mode.
struct HeadlessConfig {
    static let current = HeadlessConfig()

    /// Whether headless mode is enabled (`--headless`)
    let enabled: Bool

    /// Initial URL to load (`--url <url>`)
    let initialURL: String?

    /// MCP server port (`--port <port>`, default 8765)
    let port: UInt16

    /// Window dimensions (`--window-size <WxH>`, default 1440x900)
    let windowWidth: Int
    let windowHeight: Int

    private init() {
        let args = ProcessInfo.processInfo.arguments

        self.enabled = args.contains("--headless")

        if let urlIndex = args.firstIndex(of: "--url"), urlIndex + 1 < args.count {
            self.initialURL = args[urlIndex + 1]
        } else {
            self.initialURL = nil
        }

        if let portIndex = args.firstIndex(of: "--port"), portIndex + 1 < args.count,
           let portValue = UInt16(args[portIndex + 1]) {
            self.port = portValue
        } else {
            self.port = 8765
        }

        if let sizeIndex = args.firstIndex(of: "--window-size"), sizeIndex + 1 < args.count {
            let parts = args[sizeIndex + 1].split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 {
                self.windowWidth = parts[0]
                self.windowHeight = parts[1]
            } else {
                self.windowWidth = 1440
                self.windowHeight = 900
            }
        } else {
            self.windowWidth = 1440
            self.windowHeight = 900
        }
    }
}
