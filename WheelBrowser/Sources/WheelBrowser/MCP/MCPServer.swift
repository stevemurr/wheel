import Foundation
import Network

/// Model Context Protocol server for external client access to browser automation
@MainActor
class MCPServer: ObservableObject {
    // MARK: - Singleton

    static let shared = MCPServer()

    // MARK: - Published State

    @Published var isRunning: Bool = false
    @Published var port: UInt16 = 8765
    @Published var connectionCount: Int = 0
    @Published var lastError: String?

    // MARK: - Dependencies

    private weak var browserState: BrowserState?
    private weak var agentEngine: AgentEngine?
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    // MARK: - Tool Definitions

    private let tools: [[String: Any]] = [
        [
            "name": "browser_snapshot",
            "description": "Get a snapshot of interactive elements on the current page",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "browser_click",
            "description": "Click an element by its ID",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "elementId": ["type": "integer", "description": "The element ID from the snapshot"]
                ],
                "required": ["elementId"]
            ]
        ],
        [
            "name": "browser_type",
            "description": "Type text into an element",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "elementId": ["type": "integer", "description": "The element ID from the snapshot"],
                    "text": ["type": "string", "description": "The text to type"]
                ],
                "required": ["elementId", "text"]
            ]
        ],
        [
            "name": "browser_scroll",
            "description": "Scroll the page",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "direction": [
                        "type": "string",
                        "enum": ["up", "down", "top", "bottom"],
                        "description": "Scroll direction"
                    ]
                ],
                "required": ["direction"]
            ]
        ],
        [
            "name": "browser_navigate",
            "description": "Navigate to a URL",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "The URL to navigate to"]
                ],
                "required": ["url"]
            ]
        ],
        [
            "name": "agent_run",
            "description": "Run an autonomous agent task",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "task": ["type": "string", "description": "Description of the task to perform"]
                ],
                "required": ["task"]
            ]
        ]
    ]

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
            print("[MCP] Server starting on port \(port)")
        } catch {
            lastError = error.localizedDescription
            print("[MCP] Failed to start server: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
        connectionCount = 0
        print("[MCP] Server stopped")
    }

    // MARK: - Connection Handling

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("[MCP] Server listening on port \(port)")
            isRunning = true
        case .failed(let error):
            lastError = error.localizedDescription
            isRunning = false
            print("[MCP] Server failed: \(error)")
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connectionCount = connections.count
        print("[MCP] New connection (\(connectionCount) total)")

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
            print("[MCP] Connection ready")
        case .failed(let error):
            print("[MCP] Connection failed: \(error)")
            removeConnection(connection)
        case .cancelled:
            removeConnection(connection)
        default:
            break
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        connectionCount = connections.count
    }

    // MARK: - Data Handling

    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                if let data = data, !data.isEmpty {
                    await self?.handleRequest(data, connection: connection)
                }

                if let error = error {
                    print("[MCP] Receive error: \(error)")
                    return
                }

                if isComplete {
                    connection.cancel()
                } else {
                    self?.receiveData(from: connection)
                }
            }
        }
    }

    private func handleRequest(_ data: Data, connection: NWConnection) async {
        // Parse HTTP request to extract JSON-RPC body
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendErrorResponse(connection: connection, id: nil, code: -32700, message: "Parse error")
            return
        }

        // Find the JSON body (after the blank line in HTTP request)
        let parts = requestString.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2, let jsonData = parts[1].data(using: .utf8) else {
            sendErrorResponse(connection: connection, id: nil, code: -32700, message: "No JSON body found")
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
            return [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:] as [String: Any]
                ],
                "serverInfo": [
                    "name": "wheel-browser-mcp",
                    "version": "1.0.0"
                ]
            ]

        case "tools/list":
            return ["tools": tools]

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
        guard let browserState = browserState,
              let bridge = browserState.accessibilityBridge else {
            throw AgentError.webViewUnavailable
        }

        switch name {
        case "browser_snapshot":
            let snapshot = try await bridge.snapshot()
            return [
                "content": [
                    [
                        "type": "text",
                        "text": snapshot.textRepresentation
                    ]
                ]
            ]

        case "browser_click":
            guard let elementId = arguments["elementId"] as? Int else {
                throw AgentError.invalidRequest("Missing elementId")
            }
            try await bridge.click(elementId: elementId)
            return [
                "content": [
                    ["type": "text", "text": "Clicked element #\(elementId)"]
                ]
            ]

        case "browser_type":
            guard let elementId = arguments["elementId"] as? Int,
                  let text = arguments["text"] as? String else {
                throw AgentError.invalidRequest("Missing elementId or text")
            }
            try await bridge.type(elementId: elementId, text: text)
            return [
                "content": [
                    ["type": "text", "text": "Typed \"\(text)\" into element #\(elementId)"]
                ]
            ]

        case "browser_scroll":
            guard let direction = arguments["direction"] as? String else {
                throw AgentError.invalidRequest("Missing direction")
            }
            switch direction {
            case "up":
                try await bridge.scroll(deltaY: -300)
            case "down":
                try await bridge.scroll(deltaY: 300)
            case "top":
                try await bridge.scrollToTop()
            case "bottom":
                try await bridge.scrollToBottom()
            default:
                throw AgentError.invalidRequest("Invalid direction: \(direction)")
            }
            return [
                "content": [
                    ["type": "text", "text": "Scrolled \(direction)"]
                ]
            ]

        case "browser_navigate":
            guard let urlString = arguments["url"] as? String else {
                throw AgentError.invalidRequest("Missing url")
            }
            var url = urlString
            if !url.contains("://") {
                url = "https://\(url)"
            }
            guard let parsedURL = URL(string: url) else {
                throw AgentError.navigationFailed("Invalid URL: \(urlString)")
            }
            browserState.navigate(to: parsedURL)
            try await bridge.waitForLoad(timeout: 10.0)
            return [
                "content": [
                    ["type": "text", "text": "Navigated to \(url)"]
                ]
            ]

        case "agent_run":
            guard let agentEngine = agentEngine else {
                throw AgentError.webViewUnavailable
            }
            guard let task = arguments["task"] as? String else {
                throw AgentError.invalidRequest("Missing task")
            }
            let result = await agentEngine.run(task: task)
            return [
                "content": [
                    ["type": "text", "text": result.summary]
                ]
            ]

        default:
            throw AgentError.methodNotFound(name)
        }
    }

    // MARK: - Response Helpers

    private func sendSuccessResponse(connection: NWConnection, id: Any?, result: Any) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result
        ]
        sendJSON(connection: connection, json: response)
    }

    private func sendErrorResponse(connection: NWConnection, id: Any?, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ]
        sendJSON(connection: connection, json: response)
    }

    private func sendJSON(connection: NWConnection, json: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        // Send HTTP response
        let httpResponse = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        \r
        \(jsonString)
        """

        if let responseData = httpResponse.data(using: .utf8) {
            connection.send(content: responseData, completion: .contentProcessed { error in
                if let error = error {
                    print("[MCP] Send error: \(error)")
                }
            })
        }
    }
}
