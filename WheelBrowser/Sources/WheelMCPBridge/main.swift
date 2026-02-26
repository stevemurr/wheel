import Foundation

/// MCP stdio bridge that connects Claude Desktop to Wheel Browser
/// Uses newline-delimited JSON for stdio communication (MCP spec).
/// Reads JSON-RPC from stdin, handles initialize/tools/list locally,
/// and forwards tools/call to the running browser via HTTP.

// MARK: - Tool Definitions

let protocolVersion = "2024-11-05"

let serverInfo: [String: Any] = [
    "name": "wheel-browser-mcp",
    "version": "1.0.0"
]

let tools: [[String: Any]] = [
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
                ],
                "amount": [
                    "type": "integer",
                    "description": "Scroll pixels (default: 300)"
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
        "name": "browser_status",
        "description": "Get browser status including tabs and active tab info",
        "inputSchema": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ]
    ],
]

// MARK: - Response Helpers

func initializeResponse() -> [String: Any] {
    return [
        "protocolVersion": protocolVersion,
        "capabilities": [
            "tools": [:] as [String: Any]
        ],
        "serverInfo": serverInfo
    ]
}

func toolsListResponse() -> [String: Any] {
    return ["tools": tools]
}

// MARK: - JSON-RPC Helpers

/// Normalize id to ensure it's a valid JSON-RPC id (string or number, never null)
func normalizeId(_ id: Any?) -> Any {
    if let numId = id as? Int { return numId }
    if let numId = id as? Double { return numId }
    if let strId = id as? String { return strId }
    // Fallback to 0 if id is nil or invalid type - MCP requires string/number
    return 0
}

func makeSuccessResponse(id: Any?, result: Any) -> [String: Any] {
    return [
        "jsonrpc": "2.0",
        "id": normalizeId(id),
        "result": result
    ]
}

func makeErrorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
    return [
        "jsonrpc": "2.0",
        "id": normalizeId(id),
        "error": [
            "code": code,
            "message": message
        ]
    ]
}

func logError(_ message: String) {
    fputs("wheel-mcp-bridge: \(message)\n", stderr)
    fflush(stderr)
}

// MARK: - Newline-Delimited JSON I/O (MCP Spec)

/// Write a JSON-RPC response as a single line (MCP stdio transport)
func writeResponse(_ response: [String: Any]) {
    guard let jsonData = try? JSONSerialization.data(withJSONObject: response),
          var jsonString = String(data: jsonData, encoding: .utf8) else {
        logError("Failed to serialize response")
        return
    }

    // MCP spec: messages MUST NOT contain embedded newlines
    jsonString = jsonString.replacingOccurrences(of: "\n", with: "")
    jsonString = jsonString.replacingOccurrences(of: "\r", with: "")

    // Output as single line with newline delimiter
    print(jsonString)
    fflush(stdout)
}

// MARK: - HTTP Client for Browser Communication

func forwardToBrowser(request: [String: Any], toolName: String, completion: @escaping ([String: Any]) -> Void) {
    let port: UInt16 = 8765
    let urlString = "http://127.0.0.1:\(port)"
    let requestId = request["id"]

    guard let url = URL(string: urlString) else {
        completion(makeErrorResponse(id: requestId, code: -32603, message: "Invalid browser URL"))
        return
    }

    guard let jsonData = try? JSONSerialization.data(withJSONObject: request) else {
        completion(makeErrorResponse(id: requestId, code: -32603, message: "Failed to serialize request"))
        return
    }

    var httpRequest = URLRequest(url: url)
    httpRequest.httpMethod = "POST"
    httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    httpRequest.httpBody = jsonData

    httpRequest.timeoutInterval = 120

    let task = URLSession.shared.dataTask(with: httpRequest) { data, response, error in
        if let error = error {
            logError("Browser connection error: \(error.localizedDescription)")
            completion(makeErrorResponse(
                id: requestId,
                code: -32603,
                message: "Browser not running or MCP server not enabled. Start Wheel Browser and enable MCP in settings."
            ))
            return
        }

        guard let data = data, !data.isEmpty else {
            logError("No response data from browser")
            completion(makeErrorResponse(id: requestId, code: -32603, message: "No response from browser"))
            return
        }

        // Log raw response for debugging
        if let rawString = String(data: data, encoding: .utf8) {
            logError("Raw browser response: \(rawString.prefix(500))")
        }

        guard let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let rawString = String(data: data, encoding: .utf8) ?? "<binary>"
            logError("Failed to parse browser response: \(rawString.prefix(200))")
            completion(makeErrorResponse(id: requestId, code: -32603, message: "Invalid JSON response from browser"))
            return
        }

        // Ensure the response has the correct id from the original request
        var normalizedResponse = responseJSON
        normalizedResponse["id"] = normalizeId(requestId)
        normalizedResponse["jsonrpc"] = "2.0"

        completion(normalizedResponse)
    }
    task.resume()
}

// MARK: - Request Handler

func handleRequest(_ line: String) {
    guard let data = line.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        logError("Failed to parse request: \(line.prefix(100))")
        writeResponse(makeErrorResponse(id: 0, code: -32700, message: "Parse error"))
        return
    }

    let id = json["id"]
    guard let method = json["method"] as? String else {
        // No method means this might be a response or notification we don't handle
        return
    }

    logError("Handling method: \(method) id: \(String(describing: id))")

    switch method {
    case "initialize":
        writeResponse(makeSuccessResponse(id: id, result: initializeResponse()))

    case "notifications/initialized":
        // Notification - no response needed
        break

    case "tools/list":
        writeResponse(makeSuccessResponse(id: id, result: toolsListResponse()))

    case "tools/call":
        let params = json["params"] as? [String: Any] ?? [:]
        let toolName = params["name"] as? String ?? ""

        let semaphore = DispatchSemaphore(value: 0)
        forwardToBrowser(request: json, toolName: toolName) { response in
            writeResponse(response)
            semaphore.signal()
        }
        semaphore.wait()

    default:
        writeResponse(makeErrorResponse(id: id, code: -32601, message: "Method not found: \(method)"))
    }
}

// MARK: - Main Loop

func main() {
    // Disable buffering
    setbuf(stdout, nil)
    setbuf(stderr, nil)

    logError("Starting stdio bridge (newline-delimited JSON)...")

    // MCP stdio transport: read newline-delimited JSON
    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        handleRequest(trimmed)
    }

    logError("stdin closed, exiting")
}

main()
