import Foundation

/// Parses OpenAI Harmony-format LLM responses into (thought, AgentAction) pairs.
enum HarmonyFormatParser {

    /// Find the end of a JSON object starting at `from`, correctly skipping braces inside strings.
    /// Returns the index one past the closing `}`, or nil if no balanced close is found.
    static func findJSONEnd(in str: String, from start: String.Index) -> String.Index? {
        guard str[start] == "{" else { return nil }

        var braceCount = 0
        var inString = false
        var prevWasBackslash = false

        for idx in str.indices[start...] {
            let ch = str[idx]

            if inString {
                if ch == "\\" && !prevWasBackslash {
                    prevWasBackslash = true
                    continue
                }
                if ch == "\"" && !prevWasBackslash {
                    inString = false
                }
                prevWasBackslash = false
                continue
            }

            // Not inside a string
            switch ch {
            case "\"":
                inString = true
                prevWasBackslash = false
            case "{":
                braceCount += 1
            case "}":
                braceCount -= 1
                if braceCount == 0 {
                    return str.index(after: idx)
                }
            default:
                break
            }
        }

        return nil
    }

    /// Parse a Harmony-format response string into a thought and action.
    static func parse(_ response: String) -> (thought: String, action: AgentAction)? {
        // Check for JSON wrapper with thought/action fields
        if let messageStart = response.range(of: "<|message|>"),
           let jsonStart = response[messageStart.upperBound...].firstIndex(of: "{") {

            let jsonEnd = findJSONEnd(in: response, from: jsonStart)

            if let jsonEnd = jsonEnd {
                let jsonString = String(response[jsonStart..<jsonEnd])
                Log.Agent.debug("parseHarmonyFormat: Extracted JSON: \(jsonString)")

                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                    // Check for thought/action structure
                    if let thought = json["thought"] as? String,
                       let actionStr = json["action"] as? String {
                        Log.Agent.debug("parseHarmonyFormat: Found thought/action JSON - thought: \(thought), action: \(actionStr)")
                        if let action = AgentResponseParser.parseAction(actionStr) {
                            return (thought, action)
                        }
                    }

                    // Check for just "action" field
                    if let actionStr = json["action"] as? String {
                        Log.Agent.debug("parseHarmonyFormat: Found action-only JSON - action: \(actionStr)")
                        if let action = AgentResponseParser.parseAction(actionStr) {
                            return ("(from JSON)", action)
                        }
                    }

                    // Handle thought-only JSON: try to extract an action from the thought text
                    if let thought = json["thought"] as? String {
                        Log.Agent.debug("parseHarmonyFormat: Found thought-only JSON, attempting to extract action from thought: \(thought)")

                        if let extractedAction = AgentReasoningExtractor.extract(from: thought) {
                            Log.Agent.debug("parseHarmonyFormat: Extracted action from thought: \(extractedAction)")
                            if let action = AgentResponseParser.parseAction(extractedAction) {
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
        if let action = parseToolCall(response) {
            return ("(Harmony tool call)", action)
        }

        if response.contains("<|channel|>commentary") {
            Log.Agent.debug("parseHarmonyFormat: Response is commentary-only with no action")
        }

        Log.Agent.debug("parseHarmonyFormat: Could not extract action from Harmony format")
        return nil
    }

    /// Parse direct Harmony tool calls (browser.click, browser.type, etc.)
    static func parseToolCall(_ response: String) -> AgentAction? {
        // Handle browser.send_action format
        if response.contains("browser.send_action") {
            Log.Agent.debug("parseHarmonyToolCall: Detected browser.send_action format")

            if let messageStart = response.range(of: "<|message|>"),
               let jsonStart = response[messageStart.upperBound...].firstIndex(of: "{") {

                let jsonEnd = findJSONEnd(in: response, from: jsonStart)

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
                            let modifiers: ClickModifiers
                            if let modArray = json["modifiers"] as? [String] {
                                modifiers = ClickModifiers.from(modArray)
                            } else {
                                modifiers = .none
                            }
                            if let id = json["id"] as? Int {
                                return .click(elementId: id, modifiers: modifiers)
                            } else if let idStr = json["id"] as? String, let id = Int(idStr) {
                                return .click(elementId: id, modifiers: modifiers)
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
                        case "scrape":
                            if let url = json["url"] as? String,
                               let depth = json["depth"] as? Int,
                               let maxPages = json["maxPages"] as? Int ?? json["max_pages"] as? Int {
                                return .scrape(url: url, depth: UInt8(clamping: depth), maxPages: maxPages)
                            }
                        case "new_tab", "newtab":
                            return .newTab
                        case "open_tab", "opentab":
                            if let url = json["url"] as? String {
                                return .openTab(url: url)
                            }
                        case "switch_tab", "switchtab":
                            if let index = json["index"] as? Int {
                                return .switchTab(index: index)
                            }
                        case "extract_content", "extractcontent":
                            return .extractContent
                        case "read_links", "readlinks":
                            return .readLinks
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
                        // Try to extract modifiers array from the same JSON block
                        var modifiers = ClickModifiers.none
                        if let modRange = response.range(of: #""modifiers"\s*:\s*\[([^\]]*)\]"#, options: .regularExpression) {
                            let modStr = String(response[modRange])
                            let names = modStr.components(separatedBy: CharacterSet(charactersIn: "\"[],:"))
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty && $0 != "modifiers" }
                            modifiers = ClickModifiers.from(names)
                        }
                        Log.Agent.debug("parseHarmonyToolCall: Extracted click(id: \(id))")
                        return .click(elementId: id, modifiers: modifiers)
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
            // Try to extract direction from JSON "direction" field first
            if let dirRange = response.range(of: #""direction"\s*:\s*"(down|up|top|bottom)""#, options: .regularExpression) {
                let dirStr = String(response[dirRange])
                if let dir = dirStr.range(of: #"(down|up|top|bottom)"#, options: .regularExpression, range: dirStr.index(dirStr.startIndex, offsetBy: 12)..<dirStr.endIndex) {
                    let dirValue = String(dirStr[dir])
                    if let scrollDir = AgentAction.ScrollDirection(rawValue: dirValue) {
                        return .scroll(direction: scrollDir)
                    }
                }
            }
            // Fall back to quoted-only checks to avoid matching natural language
            if response.contains("\"down\"") {
                return .scroll(direction: .down)
            } else if response.contains("\"up\"") {
                return .scroll(direction: .up)
            } else if response.contains("\"top\"") {
                return .scroll(direction: .top)
            } else if response.contains("\"bottom\"") {
                return .scroll(direction: .bottom)
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

        // browser.read_text
        if response.contains("browser.read_text") || response.contains("read_text") {
            if let idRange = response.range(of: #""(?:element_?id|id)"\s*:\s*(\d+)"#, options: .regularExpression) {
                let idStr = String(response[idRange])
                if let numRange = idStr.range(of: #"\d+"#, options: .regularExpression) {
                    if let id = Int(idStr[numRange]) {
                        return .readText(elementId: id)
                    }
                }
            }
        }

        // browser.scrape
        if response.contains("browser.scrape") {
            if let urlRange = response.range(of: #""url"\s*:\s*"([^"]*)""#, options: .regularExpression) {
                var url = String(response[urlRange])
                if let valueStart = url.range(of: ":") {
                    url = String(url[valueStart.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                var depth: UInt8 = 1
                var maxPages = 50
                if let depthRange = response.range(of: #""depth"\s*:\s*(\d+)"#, options: .regularExpression) {
                    let depthStr = String(response[depthRange])
                    if let numRange = depthStr.range(of: #"\d+$"#, options: .regularExpression),
                       let d = UInt8(depthStr[numRange]) {
                        depth = d
                    }
                }
                if let mpRange = response.range(of: #""(?:maxPages|max_pages)"\s*:\s*(\d+)"#, options: .regularExpression) {
                    let mpStr = String(response[mpRange])
                    if let numRange = mpStr.range(of: #"\d+$"#, options: .regularExpression),
                       let mp = Int(mpStr[numRange]) {
                        maxPages = mp
                    }
                }
                return .scrape(url: url, depth: depth, maxPages: maxPages)
            }
        }

        // browser.new_tab
        if response.contains("browser.new_tab") {
            return .newTab
        }

        // browser.open_tab
        if response.contains("browser.open_tab") {
            if let urlRange = response.range(of: #""url"\s*:\s*"([^"]*)""#, options: .regularExpression) {
                var url = String(response[urlRange])
                if let valueStart = url.range(of: ":") {
                    url = String(url[valueStart.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                return .openTab(url: url)
            }
        }

        // browser.switch_tab
        if response.contains("browser.switch_tab") {
            if let idRange = response.range(of: #""index"\s*:\s*(\d+)"#, options: .regularExpression) {
                let idStr = String(response[idRange])
                if let numRange = idStr.range(of: #"\d+"#, options: .regularExpression),
                   let index = Int(idStr[numRange]) {
                    return .switchTab(index: index)
                }
            }
        }

        // browser.extract_content
        if response.contains("browser.extract_content") || response.contains("extract_content") {
            return .extractContent
        }

        // browser.read_links
        if response.contains("browser.read_links") || response.contains("read_links") {
            return .readLinks
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
}
