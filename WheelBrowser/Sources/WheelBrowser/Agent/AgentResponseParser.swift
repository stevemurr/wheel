import Foundation

/// Parses LLM responses into (thought, AgentAction) pairs.
/// Handles THOUGHT/ACTION format, Harmony format (OpenAI structured output),
/// and direct tool-call patterns.
enum AgentResponseParser {

    // MARK: - Public API

    /// Parse an LLM response string into a thought and action.
    /// Tries standard THOUGHT/ACTION format first, then falls back to Harmony format.
    static func parseResponse(_ response: String) -> (thought: String, action: AgentAction)? {
        // Try standard THOUGHT/ACTION format first
        if let thoughtMatch = response.range(of: "THOUGHT:", options: .caseInsensitive),
           let actionMatch = response.range(of: "ACTION:", options: .caseInsensitive) {

            let thoughtStart = thoughtMatch.upperBound
            let thoughtEnd = actionMatch.lowerBound

            // Ensure THOUGHT comes before ACTION in the response
            guard thoughtEnd > thoughtStart else {
                Log.Agent.warning("parseResponse: THOUGHT/ACTION markers in wrong order")
                // Fall through to other parsing methods
                return parseHarmonyFormat(response)
            }

            let thought = String(response[thoughtStart..<thoughtEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

            let actionString = String(response[actionMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            Log.Agent.debug("parseResponse: Extracted actionString = '\(actionString)'")

            if let action = parseAction(actionString) {
                return (thought, action)
            } else {
                Log.Agent.warning("parseResponse: parseAction failed for '\(actionString)'")
            }
        }

        // Fallback: Try to parse Harmony format (OpenAI's structured output format)
        if response.contains("<|") && response.contains("|>") {
            Log.Agent.info("parseResponse: Detected Harmony format, attempting to parse")

            if let result = parseHarmonyFormat(response) {
                return result
            }
        }

        Log.Agent.warning("parseResponse: Could not parse response in any format")
        return nil
    }

    /// Parse a single action string (e.g. "click(5)") into an AgentAction.
    static func parseAction(_ actionString: String) -> AgentAction? {
        var trimmed = actionString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle multi-action responses: only parse the FIRST action
        if let nextActionRange = trimmed.range(of: #"\n\s*(THOUGHT:|ACTION:)"#, options: .regularExpression) {
            trimmed = String(trimmed[..<nextActionRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            Log.Agent.info("parseAction: Truncated multi-action response to first action: '\(trimmed)'")
        }

        Log.Agent.debug("parseAction: Attempting to parse '\(trimmed)'")

        // click(id)
        if let match = trimmed.range(of: #"click\s*\(\s*(\d+)\s*\)"#, options: .regularExpression) {
            let idStr = trimmed[match].replacingOccurrences(of: "click", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let id = Int(idStr) {
                return .click(elementId: id)
            }
        }

        // type(id, "text")
        if let match = trimmed.range(of: #"type\s*\(\s*(\d+)\s*,\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let content = String(trimmed[match])
            if let idRange = content.range(of: #"\d+"#, options: .regularExpression),
               let textRange = content.range(of: #"[\"'](.+?)[\"']"#, options: .regularExpression) {
                let id = Int(content[idRange]) ?? 0
                var text = String(content[textRange])
                text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return .type(elementId: id, text: text)
            }
        }

        // press_enter
        if trimmed.lowercased().hasPrefix("press_enter") {
            return .pressEnter
        }

        // scroll(direction)
        if let match = trimmed.range(of: #"scroll\s*\(\s*(\w+)\s*\)"#, options: .regularExpression) {
            let dirStr = String(trimmed[match])
                .replacingOccurrences(of: "scroll", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if let direction = AgentAction.ScrollDirection(rawValue: dirStr) {
                return .scroll(direction: direction)
            }
        }

        // navigate("url")
        if let match = trimmed.range(of: #"navigate\s*\(\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let url = String(trimmed[match])
                .replacingOccurrences(of: "navigate", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return .navigate(url: url)
        }

        // back()
        if trimmed.lowercased().hasPrefix("back()") || trimmed.lowercased().hasPrefix("back") && trimmed.count < 10 {
            return .back
        }

        // wait_for_user("reason")
        if let match = trimmed.range(of: #"wait_for_user\s*\(\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let reason = String(trimmed[match])
                .replacingOccurrences(of: "wait_for_user", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return .waitForUser(reason: reason)
        }

        // wait(seconds)
        if let match = trimmed.range(of: #"wait\s*\(\s*([\d.]+)\s*\)"#, options: .regularExpression) {
            let secStr = String(trimmed[match])
                .replacingOccurrences(of: "wait", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let seconds = Double(secStr) {
                return .wait(seconds: seconds)
            }
        }

        // done("summary")
        if let match = trimmed.range(of: #"done\s*\(\s*[\"'](.+?)[\"']\s*\)"#, options: .regularExpression) {
            let summary = String(trimmed[match])
                .replacingOccurrences(of: "done", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            Log.Agent.info("parseAction: Matched done() with summary: \(summary)")
            return .done(summary: summary)
        }

        // Log unmatched action for debugging
        Log.Agent.debug("parseAction: No pattern matched for '\(trimmed)'")

        if trimmed.lowercased().hasPrefix("done") {
            Log.Agent.debug("parseAction: Looks like done() but didn't match regex. Check for missing quotes.")
        }

        return nil
    }

    // MARK: - Harmony Format Parsing

    /// Parse OpenAI Harmony format responses.
    private static func parseHarmonyFormat(_ response: String) -> (thought: String, action: AgentAction)? {
        // Check for JSON wrapper with thought/action fields
        if let messageStart = response.range(of: "<|message|>"),
           let jsonStart = response[messageStart.upperBound...].firstIndex(of: "{") {

            var braceCount = 0
            var jsonEnd: String.Index?
            for idx in response.indices[jsonStart...] {
                if response[idx] == "{" { braceCount += 1 }
                else if response[idx] == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        jsonEnd = response.index(after: idx)
                        break
                    }
                }
            }

            if let jsonEnd = jsonEnd {
                let jsonString = String(response[jsonStart..<jsonEnd])
                Log.Agent.debug("parseHarmonyFormat: Extracted JSON: \(jsonString)")

                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                    // Check for thought/action structure
                    if let thought = json["thought"] as? String,
                       let actionStr = json["action"] as? String {
                        Log.Agent.debug("parseHarmonyFormat: Found thought/action JSON - thought: \(thought), action: \(actionStr)")
                        if let action = parseAction(actionStr) {
                            return (thought, action)
                        }
                    }

                    // Check for just "action" field
                    if let actionStr = json["action"] as? String {
                        Log.Agent.debug("parseHarmonyFormat: Found action-only JSON - action: \(actionStr)")
                        if let action = parseAction(actionStr) {
                            return ("(from JSON)", action)
                        }
                    }

                    // Handle thought-only JSON: try to extract an action from the thought text
                    if let thought = json["thought"] as? String {
                        Log.Agent.debug("parseHarmonyFormat: Found thought-only JSON, attempting to extract action from thought: \(thought)")

                        if let extractedAction = extractActionFromReasoning(thought) {
                            Log.Agent.debug("parseHarmonyFormat: Extracted action from thought: \(extractedAction)")
                            if let action = parseAction(extractedAction) {
                                return (thought, action)
                            }
                        }

                        let thoughtLower = thought.lowercased()
                        if thoughtLower.contains("type") && thoughtLower.contains("search") {
                            Log.Agent.debug("parseHarmonyFormat: Thought mentions typing in search, but no specific action")
                        }
                        if thoughtLower.contains("press enter") || thoughtLower.contains("press_enter") {
                            return (thought, .pressEnter)
                        }
                        if thoughtLower.contains("scroll down") {
                            return (thought, .scroll(direction: .down))
                        }
                        if thoughtLower.contains("scroll up") {
                            return (thought, .scroll(direction: .up))
                        }
                    }
                }
            }
        }

        // Fall through to direct tool call patterns
        if let action = parseHarmonyToolCall(response) {
            return ("(Harmony tool call)", action)
        }

        if response.contains("<|channel|>commentary") {
            Log.Agent.debug("parseHarmonyFormat: Response is commentary-only with no action")
        }

        Log.Agent.debug("parseHarmonyFormat: Could not extract action from Harmony format")
        return nil
    }

    /// Parse direct Harmony tool calls (browser.click, browser.type, etc.)
    private static func parseHarmonyToolCall(_ response: String) -> AgentAction? {
        // Handle browser.send_action format
        if response.contains("browser.send_action") {
            Log.Agent.debug("parseHarmonyToolCall: Detected browser.send_action format")

            if let messageStart = response.range(of: "<|message|>"),
               let jsonStart = response[messageStart.upperBound...].firstIndex(of: "{") {

                var braceCount = 0
                var jsonEnd: String.Index?
                for idx in response.indices[jsonStart...] {
                    if response[idx] == "{" { braceCount += 1 }
                    else if response[idx] == "}" {
                        braceCount -= 1
                        if braceCount == 0 {
                            jsonEnd = response.index(after: idx)
                            break
                        }
                    }
                }

                if let jsonEnd = jsonEnd {
                    let jsonString = String(response[jsonStart..<jsonEnd])
                    Log.Agent.debug("parseHarmonyToolCall: send_action JSON: \(jsonString)")

                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let actionType = json["action"] as? String {

                        switch actionType.lowercased() {
                        case "navigate":
                            if let url = json["url"] as? String {
                                Log.Agent.debug("parseHarmonyToolCall: Extracted navigate(url: \(url)) from send_action")
                                return .navigate(url: url)
                            }
                        case "click":
                            if let id = json["id"] as? Int {
                                return .click(elementId: id)
                            } else if let idStr = json["id"] as? String, let id = Int(idStr) {
                                return .click(elementId: id)
                            }
                        case "type":
                            let id: Int?
                            if let intId = json["id"] as? Int {
                                id = intId
                            } else if let strId = json["id"] as? String {
                                id = Int(strId)
                            } else {
                                id = nil
                            }
                            if let id = id, let text = json["text"] as? String {
                                return .type(elementId: id, text: text)
                            }
                        case "press_enter", "pressenter", "enter":
                            return .pressEnter
                        case "scroll":
                            if let direction = json["direction"] as? String {
                                if let dir = AgentAction.ScrollDirection(rawValue: direction.lowercased()) {
                                    return .scroll(direction: dir)
                                }
                            }
                        case "done", "complete":
                            let summary = json["summary"] as? String ?? "Task completed"
                            return .done(summary: summary)
                        default:
                            Log.Agent.debug("parseHarmonyToolCall: Unknown action type '\(actionType)' in send_action")
                        }
                    }
                }
            }
        }

        // browser.click with JSON payload
        if response.contains("browser.click") {
            if let idRange = response.range(of: #""id"\s*:\s*"?(\d+)"?"#, options: .regularExpression) {
                let idSegment = String(response[idRange])
                if let digitRange = idSegment.range(of: #"\d+"#, options: .regularExpression) {
                    if let id = Int(idSegment[digitRange]) {
                        Log.Agent.debug("parseHarmonyToolCall: Extracted click(id: \(id))")
                        return .click(elementId: id)
                    }
                }
            }
        }

        // browser.type with JSON payload
        if response.contains("browser.type") {
            if let idRange = response.range(of: #""id"\s*:\s*"?(\d+)"?"#, options: .regularExpression),
               let textRange = response.range(of: #""text"\s*:\s*"([^"]*)""#, options: .regularExpression) {
                let idSegment = String(response[idRange])
                var text = String(response[textRange])
                if let valueStart = text.range(of: ":") {
                    text = String(text[valueStart.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                if let digitRange = idSegment.range(of: #"\d+"#, options: .regularExpression) {
                    if let id = Int(idSegment[digitRange]) {
                        Log.Agent.debug("parseHarmonyToolCall: Extracted type(id: \(id), text: \(text))")
                        return .type(elementId: id, text: text)
                    }
                }
            }
        }

        // browser.press_enter
        if response.contains("browser.press_enter") || response.contains("press_enter") {
            Log.Agent.debug("parseHarmonyToolCall: Extracted press_enter")
            return .pressEnter
        }

        // browser.scroll
        if response.contains("browser.scroll") {
            if response.contains("\"down\"") || response.contains("down") {
                return .scroll(direction: .down)
            } else if response.contains("\"up\"") || response.contains("up") {
                return .scroll(direction: .up)
            }
        }

        // browser.navigate
        if response.contains("browser.navigate") {
            if let urlRange = response.range(of: #""url"\s*:\s*"([^"]*)""#, options: .regularExpression) {
                var url = String(response[urlRange])
                if let valueStart = url.range(of: ":") {
                    url = String(url[valueStart.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                Log.Agent.debug("parseHarmonyToolCall: Extracted navigate(url: \(url))")
                return .navigate(url: url)
            }
        }

        // browser.done
        if response.contains("browser.done") || response.contains("task.complete") {
            if let summaryRange = response.range(of: #""summary"\s*:\s*"([^"]*)""#, options: .regularExpression) {
                var summary = String(response[summaryRange])
                if let valueStart = summary.range(of: ":") {
                    summary = String(summary[valueStart.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                return .done(summary: summary)
            }
            return .done(summary: "Task completed")
        }

        return nil
    }

    // MARK: - Reasoning Extraction

    /// Try to extract an action from reasoning content that doesn't have THOUGHT/ACTION markers.
    /// Handles reasoning models that explain what they'll do without using the required format.
    static func extractActionFromReasoning(_ reasoning: String) -> String? {
        // navigate("url") or navigate(url)
        if let match = reasoning.range(of: #"navigate\s*\(\s*[\"']?https?://[^\s\"'\)]+[\"']?\s*\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        // "Let's navigate to URL" or "navigate to URL"
        if let match = reasoning.range(of: #"(?:let's\s+)?navigate\s+(?:to\s+)?[\"']?(https?://[^\s\"']+)[\"']?"#, options: [.regularExpression, .caseInsensitive]) {
            let segment = String(reasoning[match])
            if let urlMatch = segment.range(of: #"https?://[^\s\"']+"#, options: .regularExpression) {
                let url = String(segment[urlMatch])
                return "navigate(\"\(url)\")"
            }
        }

        // type(id, "text")
        if let match = reasoning.range(of: #"type\s*\(\s*\d+\s*,\s*[\"'][^\"']+[\"']\s*\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        // click(id)
        if let match = reasoning.range(of: #"click\s*\(\s*\d+\s*\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        // press_enter
        if reasoning.range(of: #"press[_\s]?enter"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "press_enter"
        }

        // scroll(direction)
        if let match = reasoning.range(of: #"scroll\s*\(\s*(up|down|top|bottom)\s*\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        // done("summary")
        if let match = reasoning.range(of: #"done\s*\([\"'][^\"']+[\"']\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        return nil
    }
}
