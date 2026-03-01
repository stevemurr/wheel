import Foundation

/// Shared MCP tool definitions used by both MCPServer and WheelMCPBridge
enum MCPToolDefinitions {
    /// Protocol version for MCP
    static let protocolVersion = "2024-11-05"

    /// Server info
    static let serverInfo: [String: Any] = [
        "name": "wheel-browser-mcp",
        "version": "1.0.0"
    ]

    /// All available browser automation tools
    static let tools: [[String: Any]] = [
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
            "description": "Click an element by its ID, optionally with modifier keys",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "elementId": ["type": "integer", "description": "The element ID from the snapshot"],
                    "modifiers": [
                        "type": "array",
                        "items": ["type": "string", "enum": ["shift", "command", "control", "option"]],
                        "description": "Modifier keys to hold during click (e.g. command to open in new tab)"
                    ]
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
        [
            "name": "agent_run",
            "description": "Run an autonomous agent task that can browse and interact with web pages",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "task": ["type": "string", "description": "Description of the task to perform"]
                ],
                "required": ["task"]
            ]
        ],
        [
            "name": "agent_cancel",
            "description": "Cancel a running agent task",
            "inputSchema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
    ]

    /// Generate the initialize response
    static func initializeResponse() -> [String: Any] {
        return [
            "protocolVersion": protocolVersion,
            "capabilities": [
                "tools": [:] as [String: Any]
            ],
            "serverInfo": serverInfo
        ]
    }

    /// Generate the tools/list response
    static func toolsListResponse() -> [String: Any] {
        return ["tools": tools]
    }
}
