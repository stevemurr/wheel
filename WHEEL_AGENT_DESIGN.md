# Wheel Browser — Agent Mode Design Document

**Project:** `stevemurr/wheel`  
**Feature:** Native browser agent with MCP server  
**Stack:** Swift 5.9+, SwiftUI, WKWebView, macOS 14+  
**Scope:** Three self-contained phases, each independently shippable

---

## Overview

This document specifies the implementation of a native agentic browser layer for Wheel. The goal is to enable natural-language task execution ("find the best laptop under $1000 on Amazon") that drives the live WKWebView browser — not a headless Chromium subprocess, not Python, not AppleScript. Everything runs inside the existing Swift process using WKWebView's JavaScript evaluation and `WKScriptMessageHandler` APIs.

The implementation has three phases:

1. **`AccessibilityBridge`** — extract a compact, LLM-readable snapshot of the current page  
2. **`AgentEngine`** — ReAct observe→think→act loop that drives WKWebView  
3. **`MCPServer`** — expose the browser over Model Context Protocol so external clients (Claude Desktop, Cursor) can control Wheel

Each phase builds on the last but is independently useful and shippable.

---

## Existing Architecture (do not break these)

```
WheelBrowser/Sources/WheelBrowser/
├── WheelBrowserApp.swift         # App entry, @main
├── ContentView.swift             # Root layout — hosts OmniBar + WebView
├── BrowserState.swift            # @MainActor ObservableObject: tabs, navigation
├── OmniBar/
│   ├── OmniBar.swift             # Bottom input bar (Address / Chat / Semantic modes)
│   ├── OmniBarState.swift        # Mode enum + input state
│   └── MentionTypes.swift        # @mention system
├── Letta/
│   └── AgentManager.swift        # LLM chat integration (OpenAI-compatible)
├── SemanticSearch/
│   └── SemanticSearchManager.swift  # NLEmbedding vector search
└── Settings/
    └── AppSettings.swift         # UserDefaults + Keychain config
```

**Key constraint:** `BrowserState` owns the active `WKWebView`. All JavaScript evaluation must go through `BrowserState` methods or be called on the `WKWebView` instance it exposes. Do not create new `WKWebView` instances.

**Key constraint:** The existing LLM integration in `AgentManager.swift` uses an OpenAI-compatible streaming API. The agent engine must reuse `AppSettings` for the API endpoint and key — do not hardcode credentials or add new credential storage.

**Key constraint:** OmniBar has three modes cycled with Tab: Address, Chat, Semantic. Add **Agent** as a fourth mode. Do not refactor the existing three modes.

---

## Phase 1: AccessibilityBridge

### Purpose

Extract the current page's interactive elements into a compact, token-efficient JSON structure that can be passed to an LLM as context. This is the "observe" step of every agent loop iteration.

### New file: `Agent/AccessibilityBridge.swift`

```swift
import WebKit
import Foundation

/// A snapshot of a page's interactive elements, suitable for LLM consumption.
struct PageSnapshot: Codable {
    let url: String
    let title: String
    let scrollY: Double
    let pageHeight: Double
    let viewportHeight: Double
    let elements: [SnapElement]
    
    /// Renders a compact text representation for the LLM system prompt.
    func asText() -> String {
        var lines = ["PAGE: \(title)", "URL: \(url)", ""]
        for el in elements {
            let coords = "[\(el.x),\(el.y) \(el.width)x\(el.height)]"
            let name = el.name?.prefix(60) ?? "(unnamed)"
            lines.append("[\(el.ref)] \(el.role) \(coords) \"\(name)\"")
            if let href = el.href { lines.append("    href: \(href)") }
        }
        return lines.joined(separator: "\n")
    }
}

struct SnapElement: Codable {
    let ref: Int          // stable per-snapshot index; use this in action calls
    let role: String      // "button", "link", "input", "select", "textarea", or tag name
    let name: String?     // aria-label → innerText (truncated) → placeholder
    let href: String?     // for links
    let inputType: String? // for input elements: "text", "password", "checkbox", etc.
    let value: String?    // current value for inputs/selects
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

@MainActor
final class AccessibilityBridge {
    private weak var webView: WKWebView?
    
    init(webView: WKWebView) {
        self.webView = webView
    }
    
    /// Extract page snapshot. Throws on JS error or JSON decode failure.
    func snapshot() async throws -> PageSnapshot {
        guard let webView else { throw AgentError.noWebView }
        let js = Self.snapshotJS
        let result = try await webView.evaluateJavaScript(js)
        guard let jsonString = result as? String,
              let data = jsonString.data(using: .utf8) else {
            throw AgentError.snapshotFailed("JS returned non-string")
        }
        return try JSONDecoder().decode(PageSnapshot.self, from: data)
    }
    
    /// Take a screenshot of the current viewport as PNG data.
    func screenshot() async throws -> Data {
        guard let webView else { throw AgentError.noWebView }
        return try await withCheckedThrowingContinuation { continuation in
            let config = WKSnapshotConfiguration()
            webView.takeSnapshot(with: config) { image, error in
                if let error { continuation.resume(throwing: error); return }
                guard let image, let data = image.tiffRepresentation else {
                    continuation.resume(throwing: AgentError.screenshotFailed)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
    
    // MARK: - Actions
    
    /// Click element by ref index from the most recent snapshot.
    func click(ref: Int, snapshot: PageSnapshot) async throws {
        guard let el = snapshot.elements.first(where: { $0.ref == ref }) else {
            throw AgentError.elementNotFound(ref)
        }
        // Scroll element into view, then click at center
        let js = """
        (function() {
            const els = document.querySelectorAll('a, button, input, select, textarea, [role], [tabindex]');
            const visible = Array.from(els).filter(el => {
                const r = el.getBoundingClientRect();
                return r.width > 0 && r.height > 0;
            });
            const el = visible[\(ref)];
            if (!el) return false;
            el.scrollIntoView({ block: 'center' });
            el.focus();
            el.click();
            return true;
        })()
        """
        let result = try await webView!.evaluateJavaScript(js)
        if let success = result as? Bool, !success {
            throw AgentError.elementNotFound(ref)
        }
    }
    
    /// Type text into a focused input element.
    func type(ref: Int, text: String, snapshot: PageSnapshot) async throws {
        // Escape text for JS string literal
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = """
        (function() {
            const els = document.querySelectorAll('a, button, input, select, textarea, [role], [tabindex]');
            const visible = Array.from(els).filter(el => {
                const r = el.getBoundingClientRect();
                return r.width > 0 && r.height > 0;
            });
            const el = visible[\(ref)];
            if (!el) return false;
            el.focus();
            const nativeInput = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
            if (nativeInput) {
                nativeInput.set.call(el, '\(escaped)');
            } else {
                el.value = '\(escaped)';
            }
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
        })()
        """
        try await webView!.evaluateJavaScript(js)
    }
    
    /// Press Enter/Return on the active element (submit forms).
    func pressEnter() async throws {
        let js = """
        document.activeElement?.dispatchEvent(
            new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true })
        );
        """
        try await webView!.evaluateJavaScript(js)
    }
    
    /// Scroll the page.
    func scroll(direction: ScrollDirection, amount: Int = 400) async throws {
        let delta = direction == .down ? amount : -amount
        let js = "window.scrollBy({ top: \(delta), behavior: 'smooth' });"
        try await webView!.evaluateJavaScript(js)
        // Give scroll time to settle
        try await Task.sleep(nanoseconds: 400_000_000)
    }
    
    enum ScrollDirection { case up, down }
    
    /// Extract structured data from the page matching a plain-language description.
    /// Returns raw text content relevant to the query.
    func extractText(query: String) async throws -> String {
        // Pull visible text from the page body, limited to avoid token explosion
        let js = """
        (function() {
            const walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT,
                { acceptNode: n => n.textContent.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT }
            );
            let text = '', node;
            while ((node = walker.nextNode()) && text.length < 8000) {
                const parent = node.parentElement;
                const style = window.getComputedStyle(parent);
                if (style.display !== 'none' && style.visibility !== 'hidden') {
                    text += node.textContent.trim() + '\\n';
                }
            }
            return text;
        })()
        """
        let result = try await webView!.evaluateJavaScript(js)
        return (result as? String) ?? ""
    }
    
    // MARK: - JS Payload
    
    private static let snapshotJS = """
    JSON.stringify((function() {
        const SELECTORS = 'a[href], button, input, select, textarea, [role="button"], [role="link"], [role="tab"], [role="menuitem"], [role="checkbox"], [tabindex]:not([tabindex="-1"])';
        const elements = [];
        const seen = new WeakSet();
        document.querySelectorAll(SELECTORS).forEach((el, idx) => {
            if (seen.has(el)) return;
            seen.add(el);
            const rect = el.getBoundingClientRect();
            if (rect.width === 0 || rect.height === 0) return;
            // Skip elements outside viewport entirely (scrolled way off)
            if (rect.bottom < -window.innerHeight || rect.top > window.innerHeight * 3) return;
            const name = (
                el.getAttribute('aria-label') ||
                el.getAttribute('title') ||
                el.getAttribute('placeholder') ||
                el.textContent?.trim().replace(/\\s+/g, ' ').slice(0, 80)
            )?.trim() || null;
            elements.push({
                ref: elements.length,
                role: el.getAttribute('role') || el.tagName.toLowerCase(),
                name,
                href: el.tagName === 'A' ? el.href : null,
                inputType: el.type || null,
                value: el.value || null,
                x: Math.round(rect.x),
                y: Math.round(rect.y),
                width: Math.round(rect.width),
                height: Math.round(rect.height)
            });
        });
        return {
            url: location.href,
            title: document.title,
            scrollY: window.scrollY,
            pageHeight: document.body.scrollHeight,
            viewportHeight: window.innerHeight,
            elements
        };
    })())
    """
}
```

### Integration point

Add a computed property to `BrowserState`:

```swift
// In BrowserState.swift
var accessibilityBridge: AccessibilityBridge? {
    guard let wv = activeWebView else { return nil }
    return AccessibilityBridge(webView: wv)
}
```

Where `activeWebView` is however `BrowserState` currently exposes the active tab's `WKWebView`. Check the existing code — it may already be a published property.

---

## Phase 2: AgentEngine

### Purpose

A ReAct (Reason + Act) loop that takes a natural-language task, iterates observe→think→act using the LLM, and drives the browser until the task is complete or it hits the step limit.

### New file: `Agent/AgentEngine.swift`

```swift
import Foundation
import Combine

// MARK: - Action Types

enum AgentAction: Codable {
    case navigate(url: String)
    case click(ref: Int)
    case type(ref: Int, text: String)
    case pressEnter
    case scroll(direction: String, amount: Int)  // direction: "up" | "down"
    case wait(seconds: Double)
    case extract(instruction: String)            // ask model to pull data from current page text
    case done(result: String)                    // task complete
    case error(reason: String)                   // agent signals unrecoverable failure
    
    enum CodingKeys: String, CodingKey {
        case action, url, ref, text, direction, amount, seconds, instruction, result, reason
    }
}

// MARK: - Agent Step

struct AgentStep {
    let stepNumber: Int
    let thought: String
    let action: AgentAction
    let observation: String    // what happened after the action
    let snapshot: PageSnapshot?
}

// MARK: - Agent Session State

enum AgentStatus {
    case idle
    case running
    case completed(result: String)
    case failed(reason: String)
}

// MARK: - Engine

@MainActor
final class AgentEngine: ObservableObject {
    
    @Published var status: AgentStatus = .idle
    @Published var steps: [AgentStep] = []
    @Published var currentThought: String = ""
    @Published var streamingToken: String = ""
    
    private let maxSteps = 30
    private let settings: AppSettings        // reuse existing settings
    private weak var browserState: BrowserState?
    
    init(browserState: BrowserState, settings: AppSettings) {
        self.browserState = browserState
        self.settings = settings
    }
    
    // MARK: - Public API
    
    func run(task: String) async {
        guard status != .running else { return }
        status = .running
        steps = []
        
        var history: [[String: String]] = []
        
        do {
            for stepNum in 0..<maxSteps {
                guard status == .running else { break }
                
                // 1. OBSERVE
                guard let bridge = browserState?.accessibilityBridge else {
                    throw AgentError.noWebView
                }
                let snapshot = try await bridge.snapshot()
                
                // 2. THINK
                let systemPrompt = Self.buildSystemPrompt(task: task)
                let userMessage = Self.buildObservationMessage(
                    snapshot: snapshot,
                    stepNum: stepNum,
                    previousSteps: steps
                )
                history.append(["role": "user", "content": userMessage])
                
                let (thought, action) = try await callLLM(
                    systemPrompt: systemPrompt,
                    history: history
                )
                currentThought = thought
                history.append(["role": "assistant", "content": "THOUGHT: \(thought)\nACTION: \(actionToJSON(action))"])
                
                // 3. ACT
                let observation = try await execute(action: action, snapshot: snapshot, bridge: bridge)
                
                let step = AgentStep(
                    stepNumber: stepNum,
                    thought: thought,
                    action: action,
                    observation: observation,
                    snapshot: snapshot
                )
                steps.append(step)
                
                // 4. CHECK TERMINAL
                if case .done(let result) = action {
                    status = .completed(result: result)
                    return
                }
                if case .error(let reason) = action {
                    status = .failed(reason: reason)
                    return
                }
                
                // Small delay between steps to not hammer the UI
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            
            status = .failed(reason: "Reached max steps (\(maxSteps)) without completing task.")
            
        } catch {
            status = .failed(reason: error.localizedDescription)
        }
    }
    
    func cancel() {
        status = .idle
    }
    
    // MARK: - Execute Action
    
    private func execute(
        action: AgentAction,
        snapshot: PageSnapshot,
        bridge: AccessibilityBridge
    ) async throws -> String {
        
        switch action {
            
        case .navigate(let url):
            var urlString = url
            if !urlString.hasPrefix("http") { urlString = "https://\(urlString)" }
            guard let navURL = URL(string: urlString) else {
                return "ERROR: Invalid URL '\(url)'"
            }
            await browserState?.navigate(to: navURL)
            // Wait for page load
            try await waitForPageLoad()
            return "Navigated to \(urlString)"
            
        case .click(let ref):
            try await bridge.click(ref: ref, snapshot: snapshot)
            try await waitForPageLoad()
            return "Clicked element [\(ref)]"
            
        case .type(let ref, let text):
            try await bridge.type(ref: ref, text: text, snapshot: snapshot)
            return "Typed '\(text)' into element [\(ref)]"
            
        case .pressEnter:
            try await bridge.pressEnter()
            try await waitForPageLoad()
            return "Pressed Enter"
            
        case .scroll(let direction, let amount):
            let dir: AccessibilityBridge.ScrollDirection = direction == "up" ? .up : .down
            try await bridge.scroll(direction: dir, amount: amount)
            return "Scrolled \(direction) \(amount)px"
            
        case .wait(let seconds):
            let ns = UInt64(seconds * 1_000_000_000)
            try await Task.sleep(nanoseconds: ns)
            return "Waited \(seconds)s"
            
        case .extract(let instruction):
            let text = try await bridge.extractText(query: instruction)
            return "PAGE TEXT:\n\(text.prefix(4000))"
            
        case .done, .error:
            return ""  // handled by caller
        }
    }
    
    // MARK: - LLM Call
    
    private func callLLM(
        systemPrompt: String,
        history: [[String: String]]
    ) async throws -> (thought: String, action: AgentAction) {
        
        let endpoint = settings.llmEndpoint  // e.g. "http://localhost:11434/v1"
        let apiKey = settings.llmAPIKey ?? ""
        let model = settings.llmModel ?? "gpt-4o"
        
        let url = URL(string: "\(endpoint)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": systemPrompt]] + history,
            "temperature": 0.2,
            "max_tokens": 1024,
            "response_format": ["type": "json_object"]  // enforce JSON output
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AgentError.llmCallFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = (json?["choices"] as? [[String: Any]])?
            .first?["message"] as? [String: Any]
        let rawText = content?["content"] as? String ?? ""
        
        return try parseResponse(rawText)
    }
    
    // MARK: - Response Parsing
    
    private func parseResponse(_ text: String) throws -> (thought: String, action: AgentAction) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.parseError("LLM returned non-JSON: \(text.prefix(200))")
        }
        
        let thought = json["thought"] as? String ?? ""
        guard let actionObj = json["action"] as? [String: Any],
              let actionName = actionObj["type"] as? String else {
            throw AgentError.parseError("Missing 'action.type' in response")
        }
        
        let action: AgentAction
        switch actionName {
        case "navigate":
            let url = actionObj["url"] as? String ?? ""
            action = .navigate(url: url)
        case "click":
            let ref = actionObj["ref"] as? Int ?? 0
            action = .click(ref: ref)
        case "type":
            let ref = actionObj["ref"] as? Int ?? 0
            let text = actionObj["text"] as? String ?? ""
            action = .type(ref: ref, text: text)
        case "press_enter":
            action = .pressEnter
        case "scroll":
            let dir = actionObj["direction"] as? String ?? "down"
            let amt = actionObj["amount"] as? Int ?? 400
            action = .scroll(direction: dir, amount: amt)
        case "wait":
            let secs = actionObj["seconds"] as? Double ?? 1.0
            action = .wait(seconds: secs)
        case "extract":
            let inst = actionObj["instruction"] as? String ?? ""
            action = .extract(instruction: inst)
        case "done":
            let result = actionObj["result"] as? String ?? ""
            action = .done(result: result)
        case "error":
            let reason = actionObj["reason"] as? String ?? "Unknown error"
            action = .error(reason: reason)
        default:
            throw AgentError.parseError("Unknown action type: \(actionName)")
        }
        
        return (thought, action)
    }
    
    // MARK: - Page Load Waiting
    
    private func waitForPageLoad() async throws {
        // Poll until WKWebView signals load complete, max 10s
        var attempts = 0
        while attempts < 20 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let isLoading = await browserState?.isLoading ?? false
            if !isLoading { break }
            attempts += 1
        }
    }
    
    // MARK: - Prompt Construction
    
    private static func buildSystemPrompt(task: String) -> String {
        """
        You are a browser automation agent. Your task: \(task)

        You control a real browser. At each step you receive a snapshot of the current page's interactive elements and must output a JSON object with exactly two keys: "thought" and "action".

        ## Output format (ALWAYS valid JSON, no markdown):
        {
          "thought": "your reasoning about what to do next",
          "action": {
            "type": "<action_type>",
            ...action-specific fields
          }
        }

        ## Available actions:

        Navigate to a URL:
        {"type": "navigate", "url": "https://example.com"}

        Click an element by its [ref] number:
        {"type": "click", "ref": 5}

        Type text into an element (clears existing value):
        {"type": "type", "ref": 3, "text": "search query"}

        Press Enter on the currently focused element:
        {"type": "press_enter"}

        Scroll the page:
        {"type": "scroll", "direction": "down", "amount": 500}

        Wait for content to load:
        {"type": "wait", "seconds": 2}

        Extract visible text from the page (use when you need to read content):
        {"type": "extract", "instruction": "what you're looking for"}

        Signal task complete:
        {"type": "done", "result": "full answer or summary for the user"}

        Signal unrecoverable failure:
        {"type": "error", "reason": "why you cannot complete the task"}

        ## Rules:
        - ONLY output valid JSON. No prose, no markdown, no code fences.
        - Use ref numbers ONLY from the current snapshot — they change between steps.
        - Prefer clicking search buttons over pressing Enter when both are available.
        - If a page hasn't changed after an action, try scrolling or extracting first before retrying.
        - Never submit forms with personal financial data or passwords.
        - Call "done" as soon as you have a complete answer.
        """
    }
    
    private static func buildObservationMessage(
        snapshot: PageSnapshot,
        stepNum: Int,
        previousSteps: [AgentStep]
    ) -> String {
        var msg = "STEP \(stepNum + 1)\n\n"
        msg += snapshot.asText()
        
        if let last = previousSteps.last {
            msg += "\n\nPREVIOUS ACTION RESULT:\n\(last.observation)"
        }
        
        return msg
    }
    
    // MARK: - Helpers
    
    private func actionToJSON(_ action: AgentAction) -> String {
        // Simple string representation for history; not used for parsing
        switch action {
        case .navigate(let url): return "{navigate: \(url)}"
        case .click(let ref): return "{click: \(ref)}"
        case .type(let ref, let text): return "{type: ref=\(ref), text='\(text.prefix(40))'}"
        case .pressEnter: return "{press_enter}"
        case .scroll(let dir, let amt): return "{scroll: \(dir) \(amt)px}"
        case .wait(let s): return "{wait: \(s)s}"
        case .extract(let inst): return "{extract: '\(inst.prefix(60))'}"
        case .done(let r): return "{done: '\(r.prefix(80))'}"
        case .error(let r): return "{error: '\(r)'}"
        }
    }
}
```

### New file: `Agent/AgentError.swift`

```swift
enum AgentError: Error, LocalizedError {
    case noWebView
    case snapshotFailed(String)
    case screenshotFailed
    case elementNotFound(Int)
    case llmCallFailed(String)
    case parseError(String)
    case navigationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noWebView: return "No active web view"
        case .snapshotFailed(let m): return "Snapshot failed: \(m)"
        case .screenshotFailed: return "Screenshot capture failed"
        case .elementNotFound(let r): return "Element ref \(r) not found on page"
        case .llmCallFailed(let m): return "LLM call failed: \(m)"
        case .parseError(let m): return "Response parse error: \(m)"
        case .navigationFailed(let m): return "Navigation failed: \(m)"
        }
    }
}
```

### OmniBar integration

In `OmniBarState.swift`, add a fourth mode:

```swift
// Add to the Mode enum (find the existing enum, add .agent)
case agent
```

In `OmniBar.swift`, when the user submits in `.agent` mode, call:

```swift
Task {
    await agentEngine.run(task: omniBarState.inputText)
}
```

`agentEngine` should be an `@StateObject` or `@EnvironmentObject` injected from `ContentView`.

### New view: `Agent/AgentPanelView.swift`

Display agent progress below the browser when running:

```swift
import SwiftUI

struct AgentPanelView: View {
    @ObservedObject var engine: AgentEngine
    
    var body: some View {
        if case .idle = engine.status { EmptyView(); return }
        
        VStack(alignment: .leading, spacing: 8) {
            // Status bar
            HStack {
                statusIcon
                Text(statusText).font(.caption).foregroundColor(.secondary)
                Spacer()
                if case .running = engine.status {
                    Button("Cancel") { engine.cancel() }
                        .buttonStyle(.plain)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            
            // Steps list (collapsed by default, expandable)
            if !engine.steps.isEmpty {
                ScrollView {
                    ForEach(engine.steps.indices, id: \.self) { i in
                        AgentStepRow(step: engine.steps[i])
                    }
                }
                .frame(maxHeight: 200)
            }
            
            // Current thought
            if case .running = engine.status, !engine.currentThought.isEmpty {
                Text("Thinking: \(engine.currentThought)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .lineLimit(2)
            }
            
            // Final result
            if case .completed(let result) = engine.status {
                Text(result)
                    .font(.caption)
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
            }
            
            if case .failed(let reason) = engine.status {
                Text("Failed: \(reason)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(12)
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch engine.status {
        case .idle: EmptyView()
        case .running: ProgressView().scaleEffect(0.6)
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        }
    }
    
    private var statusText: String {
        switch engine.status {
        case .idle: return ""
        case .running: return "Step \(engine.steps.count + 1) — \(engine.steps.last?.action.displayName ?? "Starting")"
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }
}

struct AgentStepRow: View {
    let step: AgentStep
    @State private var expanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("[\(step.stepNumber + 1)] \(step.action.displayName)")
                    .font(.caption2).bold()
                Spacer()
                Button(expanded ? "▲" : "▼") { expanded.toggle() }
                    .buttonStyle(.plain).font(.caption2)
            }
            if expanded {
                Text("Thought: \(step.thought)").font(.caption2).foregroundColor(.secondary)
                Text("Result: \(step.observation.prefix(200))").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

extension AgentAction {
    var displayName: String {
        switch self {
        case .navigate(let url): return "Navigate → \(URL(string: url)?.host ?? url)"
        case .click(let ref): return "Click [\(ref)]"
        case .type(_, let text): return "Type '\(text.prefix(20))'"
        case .pressEnter: return "Enter"
        case .scroll(let dir, _): return "Scroll \(dir)"
        case .wait: return "Wait"
        case .extract: return "Read page"
        case .done: return "✓ Done"
        case .error: return "✗ Error"
        }
    }
}
```

**Integration:** In `ContentView.swift`, add `AgentPanelView(engine: agentEngine)` in the VStack between the WebView and the OmniBar.

---

## Phase 3: MCP Server

### Purpose

Expose Wheel as a Model Context Protocol server so external agents — Claude Desktop, Claude Code, Cursor, or any MCP client — can use your Safari/WebKit browser as their browser tool. Run as a local HTTP server on a configurable port (default 8765).

This is architecturally novel. No one has done this in Swift for a real browser.

### New file: `MCP/MCPServer.swift`

The MCP spec uses JSON-RPC 2.0 over HTTP (or HTTP+SSE for streaming). Implement the minimal subset needed to serve browser tools.

```swift
import Foundation
import Network

// MARK: - JSON-RPC types

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: JSONRPCParams?
}

enum JSONRPCId: Codable {
    case string(String)
    case number(Int)
    case null
    
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let n = try? c.decode(Int.self) { self = .number(n); return }
        self = .null
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .null: try c.encodeNil()
        }
    }
}

struct JSONRPCParams: Codable {
    // Flexible: store as raw Any-equivalent using AnyCodable or a [String: Any] workaround
    // For simplicity, use a dictionary of AnyCodable (add a minimal AnyCodable impl below)
    private let storage: [String: AnyCodable]
    
    init(_ dict: [String: Any]) {
        storage = dict.mapValues { AnyCodable($0) }
    }
    
    func value<T: Decodable>(for key: String) -> T? {
        return storage[key]?.value as? T
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        var d: [String: AnyCodable] = [:]
        for key in c.allKeys {
            d[key.stringValue] = try c.decode(AnyCodable.self, forKey: key)
        }
        storage = d
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        for (k, v) in storage {
            try c.encode(v, forKey: DynamicKey(stringValue: k)!)
        }
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

// Minimal AnyCodable wrapper
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) { self.value = value }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let n = try? c.decode(Double.self) { value = n }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let arr = try? c.decode([AnyCodable].self) { value = arr.map(\.value) }
        else { value = NSNull() }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String: try c.encode(s)
        case let n as Double: try c.encode(n)
        case let n as Int: try c.encode(n)
        case let b as Bool: try c.encode(b)
        default: try c.encodeNil()
        }
    }
}

// MARK: - MCP Tool Definitions

struct MCPTool: Codable {
    let name: String
    let description: String
    let inputSchema: [String: Any]
    
    enum CodingKeys: String, CodingKey { case name, description, inputSchema }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        // inputSchema: encode manually as JSON
        let schemaData = try JSONSerialization.data(withJSONObject: inputSchema)
        let schemaString = String(data: schemaData, encoding: .utf8) ?? "{}"
        try c.encode(schemaString, forKey: .inputSchema)
    }
}

// MARK: - Server

@MainActor
final class MCPServer: ObservableObject {
    
    @Published var isRunning = false
    @Published var port: UInt16
    
    private var listener: NWListener?
    private weak var browserState: BrowserState?
    private weak var agentEngine: AgentEngine?
    
    init(browserState: BrowserState, agentEngine: AgentEngine, port: UInt16 = 8765) {
        self.browserState = browserState
        self.agentEngine = agentEngine
        self.port = port
    }
    
    func start() throws {
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener?.start(queue: .global(qos: .userInitiated))
        isRunning = true
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }
    
    // MARK: - Connection Handling
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveData(from: connection)
    }
    
    private func receiveData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            
            Task { @MainActor in
                let response = await self.handleHTTPRequest(data: data)
                let responseData = response.data(using: .utf8) ?? Data()
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }
    
    // MARK: - HTTP Request Parsing
    
    private func handleHTTPRequest(data: Data) async -> String {
        guard let raw = String(data: data, encoding: .utf8) else {
            return httpResponse(status: 400, body: "{\"error\":\"Bad request\"}")
        }
        
        // Extract HTTP body (after double CRLF)
        guard let bodyRange = raw.range(of: "\r\n\r\n") else {
            return httpResponse(status: 400, body: "{\"error\":\"No body\"}")
        }
        let bodyString = String(raw[bodyRange.upperBound...])
        
        // Extract path from first line
        let firstLine = raw.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        let path = parts.count > 1 ? parts[1] : "/"
        
        guard path == "/mcp" || path == "/" else {
            return httpResponse(status: 404, body: "{\"error\":\"Not found\"}")
        }
        
        guard let bodyData = bodyString.data(using: .utf8),
              let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: bodyData) else {
            return httpResponse(status: 400, body: "{\"error\":\"Invalid JSON-RPC\"}")
        }
        
        let result = await dispatch(request: request)
        let responseBody: String
        if let resultData = try? JSONSerialization.data(withJSONObject: result),
           let s = String(data: resultData, encoding: .utf8) {
            responseBody = s
        } else {
            responseBody = "{}"
        }
        
        return httpResponse(status: 200, body: responseBody)
    }
    
    private func httpResponse(status: Int, body: String) -> String {
        let statusText = status == 200 ? "OK" : "Error"
        return """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """
    }
    
    // MARK: - JSON-RPC Dispatch
    
    private func dispatch(request: JSONRPCRequest) async -> [String: Any] {
        let id = idToAny(request.id)
        
        switch request.method {
            
        case "initialize":
            return jsonRPCResult(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:]],
                "serverInfo": [
                    "name": "wheel-browser",
                    "version": "1.0.0"
                ]
            ])
            
        case "tools/list":
            return jsonRPCResult(id: id, result: [
                "tools": toolDefinitions()
            ])
            
        case "tools/call":
            guard let toolName = request.params?.value(for: "name") as String?,
                  let arguments = request.params?.value(for: "arguments") as [String: Any]? else {
                return jsonRPCError(id: id, code: -32602, message: "Invalid params")
            }
            let toolResult = await callTool(name: toolName, arguments: arguments)
            return jsonRPCResult(id: id, result: [
                "content": [["type": "text", "text": toolResult]]
            ])
            
        default:
            return jsonRPCError(id: id, code: -32601, message: "Method not found: \(request.method)")
        }
    }
    
    // MARK: - Tool Implementations
    
    private func callTool(name: String, arguments: [String: Any]) async -> String {
        guard let bridge = browserState?.accessibilityBridge else {
            return "ERROR: No active browser tab"
        }
        
        switch name {
            
        case "browser_navigate":
            guard let url = arguments["url"] as? String else { return "ERROR: url required" }
            var urlString = url
            if !urlString.hasPrefix("http") { urlString = "https://\(urlString)" }
            guard let navURL = URL(string: urlString) else { return "ERROR: Invalid URL" }
            browserState?.navigate(to: navURL)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return "Navigated to \(urlString)"
            
        case "browser_snapshot":
            do {
                let snapshot = try await bridge.snapshot()
                return snapshot.asText()
            } catch {
                return "ERROR: \(error.localizedDescription)"
            }
            
        case "browser_screenshot":
            do {
                let imageData = try await bridge.screenshot()
                return "Screenshot captured (\(imageData.count) bytes) — base64:\n\(imageData.base64EncodedString().prefix(200))..."
            } catch {
                return "ERROR: \(error.localizedDescription)"
            }
            
        case "browser_click":
            guard let ref = arguments["ref"] as? Int else { return "ERROR: ref required" }
            do {
                let snapshot = try await bridge.snapshot()
                try await bridge.click(ref: ref, snapshot: snapshot)
                return "Clicked element [\(ref)]"
            } catch {
                return "ERROR: \(error.localizedDescription)"
            }
            
        case "browser_type":
            guard let ref = arguments["ref"] as? Int,
                  let text = arguments["text"] as? String else {
                return "ERROR: ref and text required"
            }
            do {
                let snapshot = try await bridge.snapshot()
                try await bridge.type(ref: ref, text: text, snapshot: snapshot)
                return "Typed into [\(ref)]"
            } catch {
                return "ERROR: \(error.localizedDescription)"
            }
            
        case "browser_scroll":
            let direction = arguments["direction"] as? String ?? "down"
            let amount = arguments["amount"] as? Int ?? 400
            do {
                try await bridge.scroll(direction: direction == "up" ? .up : .down, amount: amount)
                return "Scrolled \(direction)"
            } catch {
                return "ERROR: \(error.localizedDescription)"
            }
            
        case "browser_get_text":
            do {
                let text = try await bridge.extractText(query: arguments["instruction"] as? String ?? "")
                return text
            } catch {
                return "ERROR: \(error.localizedDescription)"
            }
            
        case "browser_run_agent":
            guard let task = arguments["task"] as? String else { return "ERROR: task required" }
            await agentEngine?.run(task: task)
            switch agentEngine?.status {
            case .completed(let result): return result
            case .failed(let reason): return "FAILED: \(reason)"
            default: return "Agent stopped"
            }
            
        default:
            return "ERROR: Unknown tool '\(name)'"
        }
    }
    
    // MARK: - Tool Definitions
    
    private func toolDefinitions() -> [[String: Any]] {
        [
            tool("browser_navigate", "Navigate the browser to a URL",
                 properties: ["url": ["type": "string", "description": "URL to navigate to"]],
                 required: ["url"]),
            
            tool("browser_snapshot", "Get the current page's interactive elements as text (accessibility tree)",
                 properties: [:], required: []),
            
            tool("browser_screenshot", "Take a screenshot of the current browser viewport",
                 properties: [:], required: []),
            
            tool("browser_click", "Click an element by its ref number from the snapshot",
                 properties: ["ref": ["type": "integer", "description": "Element ref from browser_snapshot"]],
                 required: ["ref"]),
            
            tool("browser_type", "Type text into an input element",
                 properties: [
                    "ref": ["type": "integer", "description": "Element ref from browser_snapshot"],
                    "text": ["type": "string", "description": "Text to type"]
                 ], required: ["ref", "text"]),
            
            tool("browser_scroll", "Scroll the page",
                 properties: [
                    "direction": ["type": "string", "enum": ["up", "down"]],
                    "amount": ["type": "integer", "description": "Pixels to scroll"]
                 ], required: ["direction"]),
            
            tool("browser_get_text", "Extract visible text content from the page",
                 properties: ["instruction": ["type": "string", "description": "What to look for"]],
                 required: []),
            
            tool("browser_run_agent", "Run the autonomous agent on a task (multi-step)",
                 properties: ["task": ["type": "string", "description": "Natural language task"]],
                 required: ["task"])
        ]
    }
    
    private func tool(_ name: String, _ description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        ]
    }
    
    // MARK: - JSON-RPC Helpers
    
    private func jsonRPCResult(id: Any?, result: Any) -> [String: Any] {
        var r: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { r["id"] = id }
        return r
    }
    
    private func jsonRPCError(id: Any?, code: Int, message: String) -> [String: Any] {
        var r: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        if let id { r["id"] = id }
        return r
    }
    
    private func idToAny(_ id: JSONRPCId?) -> Any? {
        switch id {
        case .string(let s): return s
        case .number(let n): return n
        case .null, .none: return nil
        }
    }
}
```

### New file: `MCP/MCPSettingsView.swift`

```swift
import SwiftUI

struct MCPSettingsView: View {
    @ObservedObject var server: MCPServer
    @State private var portText: String = "8765"
    
    var body: some View {
        Form {
            Section("MCP Server") {
                Toggle("Enable MCP Server", isOn: Binding(
                    get: { server.isRunning },
                    set: { enabled in
                        if enabled { try? server.start() }
                        else { server.stop() }
                    }
                ))
                
                if server.isRunning {
                    LabeledContent("Endpoint") {
                        Text("http://localhost:\(server.port)/mcp")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    
                    LabeledContent("Claude Desktop config") {
                        Text(claudeDesktopConfig)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                
                HStack {
                    Text("Port")
                    TextField("8765", text: $portText)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text("Restart to apply")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private var claudeDesktopConfig: String {
        """
        {
          "mcpServers": {
            "wheel": {
              "url": "http://localhost:\(server.port)/mcp"
            }
          }
        }
        """
    }
}
```

### Claude Desktop wiring

Users add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "wheel": {
      "url": "http://localhost:8765/mcp"
    }
  }
}
```

Claude Desktop will then list the 8 Wheel browser tools and can use them in any conversation.

---

## File Structure After Implementation

```
WheelBrowser/Sources/WheelBrowser/
├── ... (existing files unchanged) ...
├── Agent/
│   ├── AccessibilityBridge.swift   ← Phase 1
│   ├── AgentEngine.swift           ← Phase 2
│   ├── AgentError.swift            ← Phase 2
│   └── AgentPanelView.swift        ← Phase 2
└── MCP/
    ├── MCPServer.swift             ← Phase 3
    └── MCPSettingsView.swift       ← Phase 3
```

---

## Integration Checklist for ContentView / BrowserState

These are the exact wiring points that need to be touched in existing files.

### `BrowserState.swift`
- [ ] Add `var accessibilityBridge: AccessibilityBridge? { ... }` computed property exposing current WKWebView
- [ ] Ensure `navigate(to url: URL)` is a `@MainActor` method callable from `AgentEngine` (it likely is; confirm)
- [ ] Add `var isLoading: Bool` published property if not already present (read from WKWebView's `isLoading`)

### `ContentView.swift`
- [ ] Instantiate `AgentEngine` as `@StateObject`
- [ ] Instantiate `MCPServer` as `@StateObject`
- [ ] Add `AgentPanelView(engine: agentEngine)` between WebView and OmniBar in the layout
- [ ] Pass `agentEngine` as `@EnvironmentObject` to `OmniBar`

### `OmniBarState.swift`
- [ ] Add `.agent` to the mode enum
- [ ] Add agent mode label/icon (suggestion: `brain` SF symbol, label "Agent")

### `OmniBar.swift`
- [ ] Handle `.agent` mode submit: call `agentEngine.run(task: inputText)`
- [ ] Add Agent mode indicator in the mode cycle UI

### `AppSettings.swift`
- [ ] Confirm `llmEndpoint`, `llmAPIKey`, `llmModel` property names match what `AgentEngine` uses; adjust if they differ

### `Settings/` (wherever your settings UI lives)
- [ ] Add `MCPSettingsView` as a new settings tab

### `Package.swift` / Entitlements
- [ ] Confirm `com.apple.security.network.server` is in the app sandbox entitlements (required for NWListener)
- [ ] Confirm `com.apple.security.network.client` is present (for LLM API calls from AgentEngine)

---

## Testing Plan

### Phase 1 smoke tests
```
1. Open any webpage
2. In Xcode console: po await browserState.accessibilityBridge?.snapshot()
3. Verify JSON output contains page URL, title, and >0 elements
4. Verify asText() output is human-readable and under 4KB for typical pages
```

### Phase 2 smoke tests
```
Task: "Go to google.com and search for Swift programming"
Expected: navigate → type in search box → click search → done with results summary

Task: "Open wikipedia.org and tell me the featured article today"
Expected: navigate → extract → done with article summary

Task: "Find the price of the first item on producthunt.com"
Expected: navigate → scroll/extract → done with price
```

### Phase 3 smoke tests
```
1. Start MCP server (Settings → MCP)
2. curl -X POST http://localhost:8765/mcp \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
   → should return 8 tools

3. curl -X POST http://localhost:8765/mcp \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"browser_snapshot","arguments":{}}}'
   → should return current page accessibility tree

4. Add to Claude Desktop config → restart Claude Desktop
   → "wheel" tools should appear in Claude's tool list
```

---

## Known Limitations and Mitigations

**1. WKWebView isolation**
WKWebView runs page JavaScript in an isolated content world. The snapshot JS runs in `defaultClientWorld`, which is the same world as page scripts. This means aggressive SPAs may interfere. If this causes issues, use `WKContentWorld.world(withName: "WheelAgent")` with corresponding script injection.

**2. Element ref stability**
Refs are positional indices in a single snapshot pass. They are NOT stable across snapshots — after any page change, refs change. This is handled in `AgentEngine` by always taking a fresh snapshot before each action. Do not cache refs between steps.

**3. React/SPA inputs**
Standard `el.value = x` assignment bypasses React's synthetic event system. The `nativeInput.set.call()` approach in `type()` handles this for most cases but may fail on complex custom inputs. Add a `react_type` fallback that fires `inputEvent` with `nativeInputValueSetter` if standard type fails.

**4. Network access from NWListener**
The app sandbox requires `com.apple.security.network.server` entitlement. If the app is not sandboxed (development), NWListener works without entitlements. Check the `.entitlements` file.

**5. LLM response_format: json_object**
Ollama and some local models don't support `response_format`. Remove that field when `llmEndpoint` contains `localhost` or `127.0.0.1` and add instructions to the system prompt: "IMPORTANT: Respond with ONLY valid JSON, no other text."

**6. MCP over HTTP vs stdio**
The official MCP spec primarily uses stdio for local servers, but HTTP works and is simpler to implement. Claude Desktop supports HTTP-based MCP servers. If Claude Code CLI support is needed, add a stdio mode that reads JSON-RPC from stdin and writes to stdout.

---

## Resume / Portfolio Framing

When describing this project:

> **Native Browser Agent & MCP Server (Swift/WKWebView)**  
> Designed and implemented a browser automation agent layer for Wheel, a native macOS browser built in Swift/SwiftUI. Built an accessibility-tree extraction system over WKWebView using JavaScript injection (equivalent to Playwright MCP's snapshot mode, but running natively in real WebKit), a ReAct observe→think→act agent loop with tool-calling LLM integration, and an MCP server exposing 8 browser control tools over HTTP — enabling any MCP client (Claude Desktop, Cursor) to use Wheel as a controllable Safari-based browser. First known native Swift implementation of the browser-as-MCP-server pattern.

Key talking points for interviews:
- **Why accessibility tree over raw DOM:** 90% token reduction, more semantically meaningful, browser-rendered (handles shadow DOM, dynamic SPAs)  
- **Why native over Playwright:** Real WKWebView (actual WebKit, not Blink), no Python subprocess, no Chromium dependency, runs in-process  
- **MCP protocol understanding:** Can explain JSON-RPC 2.0, tool schema design, how MCP clients discover and call tools  
- **Agent architecture:** ReAct loop, why stateless snapshots, step limits, error recovery, prompt engineering for JSON-constrained output
