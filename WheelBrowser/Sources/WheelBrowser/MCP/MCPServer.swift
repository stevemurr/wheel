import Foundation
import Network
import WebKit
import AppKit

/// Model Context Protocol server for external client access to browser automation
@MainActor
@Observable
class MCPServer {
    // MARK: - Singleton

    static let shared = MCPServer()

    // MARK: - Observable State

    var isRunning: Bool = false
    var port: UInt16 = 8765
    var connectionCount: Int = 0
    var lastError: String?

    // MARK: - Dependencies

    @ObservationIgnored
    private weak var browserState: BrowserState?
    @ObservationIgnored
    private weak var agentEngine: AgentEngine?
    @ObservationIgnored
    private var listener: NWListener?
    @ObservationIgnored
    private var connections: [NWConnection] = []

    /// Buffer for accumulating partial HTTP requests per connection
    @ObservationIgnored
    private var connectionBuffers: [ObjectIdentifier: Data] = [:]

    // MARK: - Initialization

    private init() {}

    /// Configure the MCP server with browser dependencies
    func configure(browserState: BrowserState, agentEngine: AgentEngine) {
        self.browserState = browserState
        self.agentEngine = agentEngine
    }

    // MARK: - Server Control

    func start() {
        guard !isRunning else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection)
                }
            }
            listener?.start(queue: .main)
            isRunning = true
            lastError = nil
            Log.MCP.info("Server starting on port \(port)")
        } catch {
            lastError = error.localizedDescription
            Log.MCP.error("Failed to start server", error: error)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
        connectionCount = 0
        Log.MCP.info("Server stopped")
    }

    // MARK: - Connection Handling

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            Log.MCP.info("Server listening on port \(port)")
            isRunning = true
        case .failed(let error):
            lastError = error.localizedDescription
            isRunning = false
            Log.MCP.error("Server failed: \(error.localizedDescription)")
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        // Verify connection is from localhost only
        if case .hostPort(let host, _) = connection.endpoint {
            let hostStr = "\(host)"
            guard hostStr == "127.0.0.1" || hostStr == "::1" || hostStr == "localhost" else {
                Log.MCP.warning("Rejecting non-localhost connection from \(hostStr)")
                connection.cancel()
                return
            }
        }

        connections.append(connection)
        connectionCount = connections.count
        Log.MCP.info("New connection (\(connectionCount) total)")

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleConnectionState(connection, state: state)
            }
        }

        connection.start(queue: .main)
        receiveData(from: connection)
    }

    private func handleConnectionState(_ connection: NWConnection, state: NWConnection.State) {
        switch state {
        case .ready:
            Log.MCP.debug("Connection ready")
        case .failed(let error):
            Log.MCP.error("Connection failed: \(error.localizedDescription)")
            removeConnection(connection)
        case .cancelled:
            removeConnection(connection)
        default:
            break
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        connectionBuffers.removeValue(forKey: ObjectIdentifier(connection))
        connectionCount = connections.count
    }

    // MARK: - Data Handling

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let data = data, !data.isEmpty {
                    // Append to buffer
                    let connId = ObjectIdentifier(connection)
                    var buffer = self.connectionBuffers[connId] ?? Data()
                    buffer.append(data)
                    self.connectionBuffers[connId] = buffer

                    // Try to process complete HTTP request
                    await self.tryProcessBuffer(connection: connection)
                }

                if let error = error {
                    Log.MCP.error("Receive error: \(error.localizedDescription)")
                    connection.cancel()
                    self.removeConnection(connection)
                    return
                }

                if isComplete {
                    connection.cancel()
                    self.removeConnection(connection)
                } else {
                    self.receiveData(from: connection)
                }
            }
        }
    }

    /// Try to process a complete HTTP request from the buffer
    private func tryProcessBuffer(connection: NWConnection) async {
        let connId = ObjectIdentifier(connection)
        guard let buffer = connectionBuffers[connId],
              let requestString = String(data: buffer, encoding: .utf8) else {
            return
        }

        // Check for header/body separator
        let headerEndRange: Range<String.Index>?
        if let range = requestString.range(of: "\r\n\r\n") {
            headerEndRange = range
        } else if let range = requestString.range(of: "\n\n") {
            headerEndRange = range
        } else {
            // Haven't received full headers yet, wait for more data
            return
        }

        guard let headerEnd = headerEndRange else { return }

        let headers = String(requestString[..<headerEnd.lowerBound])
        let bodyStart = headerEnd.upperBound

        // Parse Content-Length from headers
        var contentLength = 0
        for line in headers.components(separatedBy: CharacterSet.newlines) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 && parts[0].lowercased().trimmingCharacters(in: .whitespaces) == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                break
            }
        }

        // Check if we have the complete body
        let bodyString = String(requestString[bodyStart...])
        let bodyData = bodyString.data(using: .utf8) ?? Data()

        guard bodyData.count >= contentLength else {
            // Haven't received full body yet, wait for more data
            return
        }

        // We have a complete request - clear buffer and process
        connectionBuffers.removeValue(forKey: connId)

        // Extract exactly contentLength bytes of body
        let body: String
        if contentLength > 0 {
            body = String(bodyString.prefix(contentLength))
        } else {
            body = bodyString
        }

        await handleRequest(body: body, connection: connection)
    }

    private func handleRequest(body: String, connection: NWConnection) async {
        guard !body.isEmpty, let jsonData = body.data(using: .utf8) else {
            sendErrorResponse(connection: connection, id: nil, code: -32700, message: "Empty body")
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            sendErrorResponse(connection: connection, id: nil, code: -32700, message: "Invalid JSON")
            return
        }

        let id = json["id"]
        guard let method = json["method"] as? String else {
            sendErrorResponse(connection: connection, id: id, code: -32600, message: "Invalid request: missing method")
            return
        }

        let params = json["params"] as? [String: Any] ?? [:]

        // Handle JSON-RPC methods
        do {
            let result = try await handleMethod(method, params: params)
            sendSuccessResponse(connection: connection, id: id, result: result)
        } catch let error as AgentError {
            sendErrorResponse(connection: connection, id: id, code: -32000, message: error.localizedDescription)
        } catch {
            sendErrorResponse(connection: connection, id: id, code: -32603, message: error.localizedDescription)
        }
    }

    private func handleMethod(_ method: String, params: [String: Any]) async throws -> Any {
        switch method {
        case "initialize":
            return MCPToolDefinitions.initializeResponse()

        case "tools/list":
            return MCPToolDefinitions.toolsListResponse()

        case "tools/call":
            guard let name = params["name"] as? String else {
                throw AgentError.invalidRequest("Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return try await callTool(name: name, arguments: arguments)

        default:
            throw AgentError.methodNotFound(method)
        }
    }

    private func callTool(name: String, arguments: [String: Any]) async throws -> Any {
        guard let browserState = browserState else {
            throw AgentError.webViewUnavailable
        }

        // Tools that don't require an accessibility bridge
        switch name {
        case "browser_screenshot":
            guard let webView = browserState.activeTab?.webView else {
                throw AgentError.webViewUnavailable
            }
            let config = WKSnapshotConfiguration()
            let image = try await webView.takeSnapshot(configuration: config)
            guard let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                throw AgentError.invalidRequest("Failed to capture screenshot")
            }
            let base64 = pngData.base64EncodedString()
            return [
                "content": [[
                    "type": "image",
                    "data": base64,
                    "mimeType": "image/png"
                ]]
            ]

        case "browser_new_tab":
            if let urlString = arguments["url"] as? String,
               let url = URL(string: urlString) {
                browserState.addTab(withURL: url)
            } else {
                browserState.addTab()
            }
            let newTab = browserState.activeTab
            return makeTextResponse("Opened new tab \(newTab?.id.uuidString ?? "")")

        case "browser_close_tab":
            if let tabIdString = arguments["tabId"] as? String,
               let tabId = UUID(uuidString: tabIdString) {
                browserState.closeTab(tabId)
                return makeTextResponse("Closed tab \(tabIdString)")
            } else {
                browserState.closeActiveTab()
                return makeTextResponse("Closed active tab")
            }

        case "browser_switch_tab":
            guard let tabIdString = arguments["tabId"] as? String,
                  let tabId = UUID(uuidString: tabIdString) else {
                throw AgentError.invalidRequest("Missing or invalid tabId")
            }
            guard browserState.tab(for: tabId) != nil else {
                throw AgentError.invalidRequest("Tab not found: \(tabIdString)")
            }
            browserState.selectTab(tabId)
            return makeTextResponse("Switched to tab \(tabIdString)")

        default:
            break
        }

        // Tools that require the accessibility bridge
        guard let bridge = browserState.accessibilityBridge else {
            throw AgentError.webViewUnavailable
        }

        switch name {
        case "browser_snapshot":
            let snapshot = try await bridge.snapshot()
            return makeTextResponse(snapshot.textRepresentation)

        case "browser_click":
            guard let elementId = arguments["elementId"] as? Int else {
                throw AgentError.invalidRequest("Missing elementId")
            }
            let modifiers: ClickModifiers
            if let modArray = arguments["modifiers"] as? [String] {
                modifiers = ClickModifiers.from(modArray)
            } else {
                modifiers = .none
            }
            try await bridge.click(elementId: elementId, modifiers: modifiers)
            return makeTextResponse("Clicked element #\(elementId)")

        case "browser_type":
            guard let elementId = arguments["elementId"] as? Int,
                  let text = arguments["text"] as? String else {
                throw AgentError.invalidRequest("Missing elementId or text")
            }
            try await bridge.type(elementId: elementId, text: text)
            return makeTextResponse("Typed \"\(text)\" into element #\(elementId)")

        case "browser_scroll":
            guard let direction = arguments["direction"] as? String else {
                throw AgentError.invalidRequest("Missing direction")
            }
            let amount = (arguments["amount"] as? Int) ?? 300
            switch direction {
            case "up":
                try await bridge.scroll(deltaY: Double(-amount))
            case "down":
                try await bridge.scroll(deltaY: Double(amount))
            case "top":
                try await bridge.scrollToTop()
            case "bottom":
                try await bridge.scrollToBottom()
            default:
                throw AgentError.invalidRequest("Invalid direction: \(direction)")
            }
            return makeTextResponse("Scrolled \(direction)")

        case "browser_navigate":
            guard let urlString = arguments["url"] as? String else {
                throw AgentError.invalidRequest("Missing url")
            }
            let validatedURL = try NavigationPolicy.validate(urlString)
            browserState.navigate(to: validatedURL)
            try await bridge.waitForLoad(timeout: 10.0)
            return makeTextResponse("Navigated to \(validatedURL.absoluteString)")

        case "browser_status":
            let tabs = browserState.tabs.map { tab in
                [
                    "id": tab.id.uuidString,
                    "title": tab.title,
                    "url": tab.url?.absoluteString ?? "",
                    "isActive": tab.id == browserState.activeTabId
                ] as [String: Any]
            }
            let activeTab = browserState.activeTab
            return [
                "content": [[
                    "type": "text",
                    "text": "Active: \(activeTab?.title ?? "None") (\(activeTab?.url?.absoluteString ?? ""))\nTabs: \(tabs.count)"
                ]],
                "tabs": tabs
            ]

        case "agent_run":
            guard let agentEngine = agentEngine else {
                throw AgentError.webViewUnavailable
            }
            guard let task = arguments["task"] as? String else {
                throw AgentError.invalidRequest("Missing task")
            }
            let validatedTask = try AgentInputValidator.validateTask(task)
            let result = await agentEngine.run(task: validatedTask)
            return MCPToolDefinitions.agentRunResponse(result)

        case "agent_cancel":
            guard let agentEngine = agentEngine else {
                throw AgentError.webViewUnavailable
            }
            guard agentEngine.isRunning else {
                return makeTextResponse("No agent task running")
            }
            agentEngine.cancel()
            return makeTextResponse("Agent task cancelled")

        default:
            throw AgentError.methodNotFound(name)
        }
    }

    // MARK: - Response Helpers

    /// Creates a standard MCP text response
    private func makeTextResponse(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    /// Normalize id to ensure it's a valid JSON-RPC id (string, number, or null)
    private func normalizeId(_ id: Any?) -> Any {
        if let numId = id as? Int { return numId }
        if let numId = id as? Double { return numId }
        if let strId = id as? String { return strId }
        // Preserve null distinction per JSON-RPC spec
        return NSNull()
    }

    private func sendSuccessResponse(connection: NWConnection, id: Any?, result: Any) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": normalizeId(id),
            "result": result
        ]
        sendJSON(connection: connection, json: response)
    }

    private func sendErrorResponse(connection: NWConnection, id: Any?, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": normalizeId(id),
            "error": [
                "code": code,
                "message": message
            ]
        ]
        sendJSON(connection: connection, json: response)
    }

    private func sendJSON(connection: NWConnection, json: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else {
            return
        }

        // Build HTTP headers and append JSON data directly (avoids double serialization)
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        \r

        """

        var responseData = Data(headers.utf8)
        responseData.append(jsonData)

        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                Log.MCP.error("Send error: \(error.localizedDescription)")
            }
        })
    }
}
