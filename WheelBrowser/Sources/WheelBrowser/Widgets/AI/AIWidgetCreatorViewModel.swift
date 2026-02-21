import Foundation
import SwiftUI
import Combine

/// View model for the AI widget creator interface
@MainActor
final class AIWidgetCreatorViewModel: ObservableObject {
    // MARK: - Published State

    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isGenerating: Bool = false
    @Published var previewConfig: AIWidgetConfig?
    @Published var previewContent: ExtractedContent = .empty
    @Published var isLoadingPreview: Bool = false
    @Published var error: String?

    // MARK: - Dependencies

    private let settings = AppSettings.shared
    private let fetcher = AIWidgetContentFetcher()

    // MARK: - Chat Message

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        let content: String
        let timestamp: Date

        enum Role {
            case user
            case assistant
            case system
        }
    }

    // MARK: - Initialization

    init() {
        messages.append(ChatMessage(
            role: .system,
            content: "Describe the widget you want to create. For example:\n\n• \"Show top 5 Hacker News stories\"\n• \"Display the current weather for San Francisco\"\n• \"List latest posts from r/swift\"",
            timestamp: Date()
        ))
    }

    // MARK: - Public Methods

    func sendMessage() async {
        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, content: userMessage, timestamp: Date()))

        isGenerating = true
        error = nil

        do {
            let config = try await generateWidgetConfig(prompt: userMessage)
            previewConfig = config

            messages.append(ChatMessage(
                role: .assistant,
                content: "I've created a widget configuration for \"\(config.name)\". Loading preview...",
                timestamp: Date()
            ))

            // Fetch preview content
            await loadPreview()

        } catch {
            self.error = error.localizedDescription
            messages.append(ChatMessage(
                role: .assistant,
                content: "Sorry, I couldn't generate that widget: \(error.localizedDescription)",
                timestamp: Date()
            ))
        }

        isGenerating = false
    }

    func refineWidget(instruction: String) async {
        guard let currentConfig = previewConfig else { return }

        messages.append(ChatMessage(role: .user, content: instruction, timestamp: Date()))
        isGenerating = true
        error = nil

        do {
            let refinedConfig = try await refineWidgetConfig(current: currentConfig, instruction: instruction)
            previewConfig = refinedConfig

            messages.append(ChatMessage(
                role: .assistant,
                content: "Updated the widget configuration. Reloading preview...",
                timestamp: Date()
            ))

            await loadPreview()

        } catch {
            self.error = error.localizedDescription
            messages.append(ChatMessage(
                role: .assistant,
                content: "Couldn't apply that change: \(error.localizedDescription)",
                timestamp: Date()
            ))
        }

        isGenerating = false
    }

    func loadPreview() async {
        guard let config = previewConfig else { return }

        isLoadingPreview = true
        defer { isLoadingPreview = false }

        do {
            previewContent = try await fetcher.fetch(config: config)

            if previewContent.items.isEmpty {
                messages.append(ChatMessage(
                    role: .assistant,
                    content: "The widget loaded but found no items. You might want to try a different source or adjust the selectors.",
                    timestamp: Date()
                ))
            }
        } catch {
            previewContent = ExtractedContent(error: error.localizedDescription)
            messages.append(ChatMessage(
                role: .assistant,
                content: "Preview failed: \(error.localizedDescription). Try a different approach?",
                timestamp: Date()
            ))
        }
    }

    func createWidget() -> AIWidget? {
        guard let config = previewConfig else { return nil }
        let widget = AIWidget(config: config)
        widget.content = previewContent
        widget.startAutoRefresh()
        return widget
    }

    // MARK: - LLM Integration

    private func generateWidgetConfig(prompt: String) async throws -> AIWidgetConfig {
        let systemPrompt = """
        You are a widget configuration generator. Given a user's description, generate a JSON configuration for a web widget.

        The configuration schema is:
        {
          "name": "Widget Name",
          "description": "Brief description",
          "iconName": "SF Symbol name (e.g., newspaper, cloud.sun, chart.line, bitcoinsign.circle, clock)",
          "source": {
            "type": "urlFetch" or "jsonApi" or "rssFeed" or "local",
            "url": "https://..." (empty string for local),
            "headers": {},
            "localConfig": {
              "widgetType": "worldClock" or "countdown" or "dateDisplay",
              "parameters": {"key": "value"}
            }
          },
          "extraction": {
            "type": "css" or "jsonPath" or "rss",
            "selectors": {"fieldName": "CSS selector"},
            "jsonPaths": {"fieldName": "json.path.to.value"},
            "itemSelector": "CSS selector or JSON path for list items (optional)"
          },
          "display": {
            "layout": "list" or "cards" or "singleValue" or "markdown",
            "template": "",
            "itemLimit": 5,
            "showTitle": true
          },
          "refresh": {
            "intervalMinutes": 30,
            "autoRefresh": true
          }
        }

        IMPORTANT EXAMPLES:

        For CLOCKS/TIME with multiple timezones, use "local" source type:
        {
          "name": "World Clock",
          "description": "Time in multiple cities",
          "iconName": "clock",
          "source": {
            "type": "local",
            "url": "",
            "headers": {},
            "localConfig": {
              "widgetType": "worldClock",
              "parameters": {
                "timezones": "America/Los_Angeles,Asia/Shanghai,Europe/Copenhagen",
                "label_America/Los_Angeles": "PST",
                "label_Asia/Shanghai": "Beijing",
                "label_Europe/Copenhagen": "Copenhagen"
              }
            }
          },
          "extraction": {"type": "css", "selectors": {}},
          "display": {"layout": "list", "template": "", "itemLimit": 10, "showTitle": true},
          "refresh": {"intervalMinutes": 1, "autoRefresh": true}
        }

        Common timezone identifiers:
        - America/New_York (EST/EDT), America/Los_Angeles (PST/PDT), America/Chicago (CST/CDT)
        - Europe/London (GMT/BST), Europe/Paris, Europe/Berlin, Europe/Copenhagen
        - Asia/Tokyo, Asia/Shanghai (Beijing), Asia/Singapore, Asia/Dubai
        - Australia/Sydney, Pacific/Auckland

        For COUNTDOWN timers:
        {
          "name": "Event Countdown",
          "description": "Days until event",
          "iconName": "timer",
          "source": {
            "type": "local",
            "url": "",
            "headers": {},
            "localConfig": {
              "widgetType": "countdown",
              "parameters": {
                "targetDate": "2024-12-31T00:00:00Z",
                "eventName": "New Year"
              }
            }
          },
          "extraction": {"type": "css", "selectors": {}},
          "display": {"layout": "singleValue", "template": "", "itemLimit": 1, "showTitle": true},
          "refresh": {"intervalMinutes": 1, "autoRefresh": true}
        }

        For Bitcoin/Crypto prices, use CoinGecko API:
        {
          "name": "Bitcoin Price",
          "description": "Current BTC price",
          "iconName": "bitcoinsign.circle",
          "source": {"type": "jsonApi", "url": "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd", "headers": {}},
          "extraction": {"type": "jsonPath", "jsonPaths": {"value": "bitcoin.usd"}, "selectors": {}},
          "display": {"layout": "singleValue", "template": "", "itemLimit": 1, "showTitle": true},
          "refresh": {"intervalMinutes": 5, "autoRefresh": true}
        }

        For Hacker News:
        {
          "name": "Hacker News",
          "description": "Top stories",
          "iconName": "newspaper",
          "source": {"type": "urlFetch", "url": "https://news.ycombinator.com", "headers": {}},
          "extraction": {"type": "css", "selectors": {"title": "a", "link": "a"}, "itemSelector": ".titleline"},
          "display": {"layout": "list", "template": "", "itemLimit": 5, "showTitle": true},
          "refresh": {"intervalMinutes": 30, "autoRefresh": true}
        }

        For Reddit, use RSS:
        {
          "name": "r/swift",
          "description": "Latest posts",
          "iconName": "bubble.left.and.bubble.right",
          "source": {"type": "rssFeed", "url": "https://www.reddit.com/r/swift/.rss", "headers": {}},
          "extraction": {"type": "rss", "selectors": {}},
          "display": {"layout": "list", "template": "", "itemLimit": 5, "showTitle": true},
          "refresh": {"intervalMinutes": 15, "autoRefresh": true}
        }

        Standard fields to extract: title, description, link, date, author, value, label

        Respond ONLY with valid JSON. No markdown code blocks. No explanation text.
        """

        let response = try await callLLM(systemPrompt: systemPrompt, userPrompt: prompt)
        return try parseConfigFromResponse(response)
    }

    private func refineWidgetConfig(current: AIWidgetConfig, instruction: String) async throws -> AIWidgetConfig {
        let currentJSON = try JSONEncoder().encode(current)
        let currentString = String(data: currentJSON, encoding: .utf8) ?? "{}"

        let systemPrompt = """
        You are refining an existing widget configuration. Apply the user's instruction to modify it.

        Current configuration:
        \(currentString)

        Rules:
        - Make minimal changes to satisfy the request
        - Preserve fields that aren't affected
        - Respond ONLY with the complete updated JSON configuration
        """

        let response = try await callLLM(systemPrompt: systemPrompt, userPrompt: instruction)
        return try parseConfigFromResponse(response)
    }

    private func callLLM(systemPrompt: String, userPrompt: String) async throws -> String {
        guard let baseURL = settings.llmBaseURL else {
            throw GenerationError.llmNotConfigured
        }

        let endpoint = baseURL.appendingPathComponent("chat/completions")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if settings.useAPIKey && settings.hasAPIKey {
            request.setValue("Bearer \(settings.llmAPIKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": settings.selectedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationError.llmRequestFailed("No HTTP response received")
        }

        let responseString = String(data: data, encoding: .utf8) ?? "(non-UTF8 data)"
        print("[AIWidgetCreator] LLM response status: \(httpResponse.statusCode)")
        print("[AIWidgetCreator] LLM response body: \(responseString.prefix(500))...")

        guard (200..<300).contains(httpResponse.statusCode) else {
            // Try to extract error message from response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GenerationError.llmRequestFailed("API error: \(message)")
            }
            throw GenerationError.llmRequestFailed("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GenerationError.invalidResponse("Response is not valid JSON: \(responseString.prefix(200))")
        }

        // Try standard OpenAI format: choices[0].message.content
        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        // Try Anthropic format: content[0].text
        if let content = json["content"] as? [[String: Any]],
           let firstContent = content.first,
           let text = firstContent["text"] as? String {
            return text
        }

        // Try simple text response
        if let text = json["text"] as? String {
            return text
        }

        // Try response field
        if let response = json["response"] as? String {
            return response
        }

        // Check for error in response
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw GenerationError.llmRequestFailed("API error: \(message)")
        }

        throw GenerationError.invalidResponse("Unrecognized response format. Keys: \(json.keys.joined(separator: ", "))")
    }

    private func parseConfigFromResponse(_ response: String) throws -> AIWidgetConfig {
        // Extract JSON from response - try multiple strategies
        var jsonString = extractJSON(from: response)
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[AIWidgetCreator] Extracted JSON:\n\(jsonString)")

        guard let data = jsonString.data(using: .utf8) else {
            throw GenerationError.invalidJSON("Could not convert to data")
        }

        // First try strict decoding
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AIWidgetConfig.self, from: data)
        } catch let decodingError as DecodingError {
            print("[AIWidgetCreator] Strict decode failed: \(decodingError)")

            // Try flexible parsing as fallback
            if let config = try? parseFlexibleConfig(from: data) {
                return config
            }

            // Provide detailed error message
            let errorDetail = describeDecodingError(decodingError)
            throw GenerationError.invalidJSON(errorDetail)
        } catch {
            print("[AIWidgetCreator] Parse error: \(error)")
            throw GenerationError.invalidJSON(error.localizedDescription)
        }
    }

    private func extractJSON(from response: String) -> String {
        // Strategy 1: Look for ```json code block
        if let start = response.range(of: "```json"),
           let end = response.range(of: "```", range: start.upperBound..<response.endIndex) {
            return String(response[start.upperBound..<end.lowerBound])
        }

        // Strategy 2: Look for ``` code block
        if let start = response.range(of: "```"),
           let end = response.range(of: "```", range: start.upperBound..<response.endIndex) {
            return String(response[start.upperBound..<end.lowerBound])
        }

        // Strategy 3: Find JSON object by looking for { ... }
        if let start = response.firstIndex(of: "{"),
           let end = response.lastIndex(of: "}") {
            return String(response[start...end])
        }

        return response
    }

    private func parseFlexibleConfig(from data: Data) throws -> AIWidgetConfig {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GenerationError.invalidJSON("Not a JSON object")
        }

        // Extract with defaults for missing fields
        let name = json["name"] as? String ?? "Custom Widget"
        let description = json["description"] as? String ?? ""
        let iconName = json["iconName"] as? String ?? "sparkles"

        // Parse source
        guard let sourceDict = json["source"] as? [String: Any],
              let sourceTypeStr = sourceDict["type"] as? String,
              let sourceType = DataSource.SourceType(rawValue: sourceTypeStr) else {
            throw GenerationError.invalidJSON("Missing or invalid 'source' configuration")
        }

        let url = sourceDict["url"] as? String ?? ""
        let headers = sourceDict["headers"] as? [String: String] ?? [:]

        // Parse localConfig if present (for local widgets)
        var localConfig: LocalConfig? = nil
        if let localConfigDict = sourceDict["localConfig"] as? [String: Any],
           let widgetTypeStr = localConfigDict["widgetType"] as? String,
           let widgetType = LocalConfig.LocalWidgetType(rawValue: widgetTypeStr) {
            let parameters = localConfigDict["parameters"] as? [String: String] ?? [:]
            localConfig = LocalConfig(widgetType: widgetType, parameters: parameters)
        }

        let source = DataSource(type: sourceType, url: url, headers: headers, localConfig: localConfig)

        // Parse extraction
        guard let extractionDict = json["extraction"] as? [String: Any] else {
            throw GenerationError.invalidJSON("Missing 'extraction' configuration")
        }
        let extractionTypeStr = extractionDict["type"] as? String ?? "css"
        let extractionType = ExtractionConfig.ExtractionType(rawValue: extractionTypeStr) ?? .css
        let selectors = extractionDict["selectors"] as? [String: String] ?? [:]
        let jsonPaths = extractionDict["jsonPaths"] as? [String: String]
        let itemSelector = extractionDict["itemSelector"] as? String
        let extraction = ExtractionConfig(
            type: extractionType,
            selectors: selectors,
            jsonPaths: jsonPaths,
            itemSelector: itemSelector
        )

        // Parse display
        let displayDict = json["display"] as? [String: Any] ?? [:]
        let layoutStr = displayDict["layout"] as? String ?? "list"
        let layout = DisplayConfig.LayoutType(rawValue: layoutStr) ?? .list
        let template = displayDict["template"] as? String ?? ""
        let itemLimit = displayDict["itemLimit"] as? Int ?? 5
        let showTitle = displayDict["showTitle"] as? Bool ?? true
        let accentColor = displayDict["accentColor"] as? String
        let display = DisplayConfig(
            layout: layout,
            template: template,
            itemLimit: itemLimit,
            showTitle: showTitle,
            accentColor: accentColor
        )

        // Parse refresh
        let refreshDict = json["refresh"] as? [String: Any] ?? [:]
        let intervalMinutes = refreshDict["intervalMinutes"] as? Int ?? 30
        let autoRefresh = refreshDict["autoRefresh"] as? Bool ?? true
        let refresh = RefreshConfig(intervalMinutes: intervalMinutes, autoRefresh: autoRefresh)

        return AIWidgetConfig(
            name: name,
            description: description,
            iconName: iconName,
            source: source,
            extraction: extraction,
            display: display,
            refresh: refresh
        )
    }

    private func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing field '\(key.stringValue)' in \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Wrong type for '\(path)': expected \(type)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Null value for '\(path)': expected \(type)"
        case .dataCorrupted(let context):
            return "Corrupted data: \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    // MARK: - Errors

    enum GenerationError: LocalizedError {
        case llmNotConfigured
        case llmRequestFailed(String)
        case invalidResponse(String)
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM endpoint not configured. Check Settings."
            case .llmRequestFailed(let detail):
                return "LLM request failed: \(detail)"
            case .invalidResponse(let detail):
                return "Invalid LLM response: \(detail)"
            case .invalidJSON(let detail):
                return "Could not parse widget configuration: \(detail)"
            }
        }
    }
}

// MARK: - Example Prompts

extension AIWidgetCreatorViewModel {
    static let examplePrompts = [
        "Show top 5 Hacker News stories",
        "Latest posts from r/programming",
        "Display Bitcoin price",
        "World clock for NYC, London, Tokyo",
        "Countdown to New Year 2025",
        "Latest tech news headlines"
    ]
}
