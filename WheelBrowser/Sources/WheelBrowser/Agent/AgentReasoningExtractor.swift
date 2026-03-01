import Foundation

/// Extracts action strings from free-form reasoning text produced by LLMs
/// that don't follow the structured THOUGHT/ACTION format.
enum AgentReasoningExtractor {

    /// Try to extract an action string from reasoning content.
    /// Returns a parseable action string like "click(5)" or "navigate(\"url\")" if found.
    static func extract(from reasoning: String) -> String? {
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

        // read_text(id)
        if let match = reasoning.range(of: #"read_text\s*\(\s*\d+\s*\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        // done("summary")
        if let match = reasoning.range(of: #"done\s*\([\"'][^\"']+[\"']\)"#, options: [.regularExpression, .caseInsensitive]) {
            return String(reasoning[match])
        }

        return nil
    }
}
