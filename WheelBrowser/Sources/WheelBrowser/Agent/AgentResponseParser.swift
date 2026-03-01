import Foundation

/// Parses LLM responses into (thought, AgentAction) pairs.
/// Coordinates between standard THOUGHT/ACTION format and Harmony format parsers.
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
                return HarmonyFormatParser.parse(response)
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

            if let result = HarmonyFormatParser.parse(response) {
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
}
