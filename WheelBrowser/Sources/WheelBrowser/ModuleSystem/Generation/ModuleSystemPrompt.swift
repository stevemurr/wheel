import Foundation

/// Assembles the system prompt for module generation.
/// Teaches the LLM the module manifest format and the wheel.* API.
enum ModuleSystemPrompt {

    /// Build the full system prompt for generating a new module.
    static func build() -> String {
        [
            preamble,
            "",
            "## Module Manifest Schema",
            "",
            manifestSchema,
            "",
            "## Trigger Types",
            "",
            triggerDocs,
            "",
            "## Permissions",
            "",
            permissionDocs,
            "",
            "## wheel.* Content Script API (runs in page context)",
            "",
            contentScriptAPI,
            "",
            "## wheel.* Background Script API (runs in JSContext, no DOM)",
            "",
            backgroundScriptAPI,
            "",
            "## Content Rules (WKContentRuleList format)",
            "",
            contentRulesDocs,
            "",
            "## Examples",
            "",
            examples,
            "",
            "## Rules",
            "",
            rules,
        ].joined(separator: "\n")
    }

    /// Build a system prompt for editing an existing module.
    static func buildForEdit(currentManifest: String) -> String {
        [
            editPreamble,
            "",
            "## Current Module Manifest",
            "",
            "```json",
            currentManifest,
            "```",
            "",
            "## Module Manifest Schema",
            "",
            manifestSchema,
            "",
            "## wheel.* Content Script API",
            "",
            contentScriptAPI,
            "",
            "## wheel.* Background Script API",
            "",
            backgroundScriptAPI,
            "",
            "## Rules",
            "",
            rules,
        ].joined(separator: "\n")
    }

    // MARK: - Sections

    private static let preamble = """
    You are a module generator for the Wheel browser. Given a user's description, you generate a \
    JSON module manifest that implements the requested functionality.

    A Module is the universal primitive — it can be a widget (NTP dashboard), an extension \
    (page modifications), a skill (LLM tool), or a blocker (ad/tracker blocking).

    Your output must be valid JSON conforming to the ModuleManifest schema. \
    Do NOT include any text outside the JSON object. No markdown code fences.
    """

    private static let editPreamble = """
    You are editing an existing module for the Wheel browser. The user wants to modify its behavior. \
    You will receive the current module manifest and the user's edit request.

    Output the COMPLETE updated manifest as valid JSON. Preserve the `id` field. \
    Do NOT include any text outside the JSON object. No markdown code fences.
    """

    private static let manifestSchema = """
    ```json
    {
      "id": "UUID (preserve on edits, omit for new modules)",
      "name": "string — display name",
      "description": "string — what this module does",
      "version": "number — auto-incremented on edits",
      "permissions": ["array of permission strings"],
      "triggers": [
        {
          "type": "page_load | manual | schedule | always",
          "url_pattern": "string (required for page_load, e.g. '*' or '*.example.com/*')",
          "interval_seconds": "number (required for schedule, minimum 300)"
        }
      ],
      "content_rules": "[optional] array of WKContentRuleList rule objects for network blocking",
      "styles": "[optional] array of CSS strings injected into matching pages",
      "content_script": "[optional] JavaScript string executed in page context (has DOM access)",
      "background_script": "[optional] JavaScript string executed in JSContext (no DOM, has wheel.fetch)"
    }
    ```
    """

    private static let triggerDocs = """
    | Type | When | Requirements |
    |------|------|-------------|
    | `page_load` | When a matching page loads | `url_pattern` required |
    | `manual` | Invoked by user or LLM tool call | No extra fields |
    | `schedule` | Periodically | `interval_seconds` required (≥ 300) |
    | `always` | Active for all pages (content_rules only) | Only with content_rules |
    """

    private static let permissionDocs = """
    | Permission | Purpose |
    |-----------|---------|
    | `dom.query` | Read DOM elements (query, queryAll, getText) |
    | `dom.modify` | Modify/remove DOM elements |
    | `dom.css_inject` | Inject/remove CSS stylesheets |
    | `dom.observe` | MutationObserver for DOM changes |
    | `storage.local` | Per-module key-value store (512KB quota) |
    | `network.fetch` | HTTPS requests (10 req/min, 1MB response cap) |
    | `schedule` | Background scheduling (min 5 min interval) |
    | `notifications` | Native macOS notifications |
    | `content_rules` | WKContentRuleList network blocking |
    | `page.read` | Read current URL, title, domain |
    """

    private static let contentScriptAPI = """
    ```javascript
    // DOM (requires dom.query)
    wheel.dom.query(selector)           // → {text, html, attrs} or null
    wheel.dom.queryAll(selector)        // → array of {text, html, attrs}
    wheel.dom.getText(selector)         // → text string or null

    // DOM modification (requires dom.modify)
    wheel.dom.remove(selector)          // remove matching elements
    wheel.dom.setAttribute(sel, attr, val)
    wheel.dom.addClass(sel, className)

    // CSS (requires dom.css_inject)
    wheel.dom.injectCSS(id, cssString)  // inject <style> with ID
    wheel.dom.removeCSS(id)             // remove injected <style>

    // DOM observation (requires dom.observe)
    wheel.dom.observe(selector, callback)  // MutationObserver wrapper

    // Page context (requires page.read)
    wheel.page.url                      // current URL
    wheel.page.title                    // page title
    wheel.page.domain                   // hostname

    // Storage (requires storage.local)
    await wheel.storage.get(key)        // returns value or null
    await wheel.storage.set(key, value) // stores value
    await wheel.storage.remove(key)     // removes key

    // Messaging
    wheel.message.send(type, data)      // send to background script
    wheel.message.on(type, callback)    // receive from background

    // Result (for skills — returns data to LLM)
    wheel.result(data)                  // structured data returned to caller
    ```
    """

    private static let backgroundScriptAPI = """
    ```javascript
    // Network (requires network.fetch)
    wheel.fetch(url, options)           // HTTPS only, returns parsed JSON or text

    // Storage (requires storage.local)
    wheel.storage.get(key)
    wheel.storage.set(key, value)
    wheel.storage.remove(key)

    // Widget rendering
    wheel.render(renderSpec)            // output to NTP widget panel
    // renderSpec format:
    // { type: "stat_card", label: "BTC", value: "$67,234", delta: { value: 2.3, label: "+2.3%" } }
    // { type: "list", title: "Top Posts", items: [{headline: "...", subheadline: "..."}] }
    // { type: "chart", chart_type: "line", title: "...", data: [...], x_field: "...", y_field: "..." }
    // { type: "table", columns: [{key: "...", label: "..."}], rows: [...] }

    // Scheduling (requires schedule)
    wheel.schedule.setInterval(callback, ms)  // min 5 minutes

    // Notifications (requires notifications)
    wheel.notify(title, body)

    // Messaging
    wheel.message.send(type, data)
    wheel.message.on(type, callback)

    // Result (for skills)
    wheel.result(data)
    ```
    """

    private static let contentRulesDocs = """
    Content rules use Apple's WKContentRuleList JSON format (similar to Safari Content Blockers).
    Each rule is an object with `trigger` and `action`:

    ```json
    [
      {
        "trigger": { "url-filter": ".*\\\\.doubleclick\\\\.net" },
        "action": { "type": "block" }
      },
      {
        "trigger": { "url-filter": ".*", "resource-type": ["script"], "if-domain": ["example.com"] },
        "action": { "type": "block" }
      }
    ]
    ```

    Trigger fields: `url-filter` (regex), `resource-type`, `if-domain`, `unless-domain`, `load-type`.
    Action types: `block`, `block-cookies`, `css-display-none` (with `selector` field).
    """

    private static let examples = """
    ### Example 1: Ad Blocker (content_rules only)

    User: "Build me an ad blocker"

    ```json
    {
      "name": "Ad Blocker",
      "description": "Blocks common ad networks and tracking scripts",
      "permissions": ["content_rules"],
      "triggers": [{ "type": "always" }],
      "content_rules": [
        { "trigger": { "url-filter": ".*\\\\.doubleclick\\\\.net" }, "action": { "type": "block" } },
        { "trigger": { "url-filter": ".*\\\\.googlesyndication\\\\.com" }, "action": { "type": "block" } },
        { "trigger": { "url-filter": ".*\\\\.adnxs\\\\.com" }, "action": { "type": "block" } },
        { "trigger": { "url-filter": ".*\\\\.facebook\\\\.com/tr" }, "action": { "type": "block" } },
        { "trigger": { "url-filter": ".*google-analytics\\\\.com" }, "action": { "type": "block" } }
      ]
    }
    ```

    ### Example 2: Dark Mode Extension (CSS + content script)

    User: "Make all websites dark mode"

    ```json
    {
      "name": "Dark Mode",
      "description": "Inverts colors on all web pages, preserving images",
      "permissions": ["dom.css_inject", "storage.local", "page.read"],
      "triggers": [{ "type": "page_load", "url_pattern": "*" }],
      "styles": [
        "html { filter: invert(1) hue-rotate(180deg); } img, video, canvas { filter: invert(1) hue-rotate(180deg); }"
      ],
      "content_script": "const enabled = wheel.storage.get('enabled_' + wheel.page.domain); if (enabled === false) wheel.dom.removeCSS('dark-mode');"
    }
    ```

    ### Example 3: Bitcoin Price Widget (background script)

    User: "Show me a Bitcoin price widget"

    ```json
    {
      "name": "Bitcoin Price",
      "description": "Shows current Bitcoin price with 24h change",
      "permissions": ["network.fetch", "schedule"],
      "triggers": [{ "type": "schedule", "interval_seconds": 300 }],
      "background_script": "const data = wheel.fetch('https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true'); const price = data.bitcoin.usd; const change = data.bitcoin.usd_24h_change; wheel.render({ type: 'stat_card', label: 'Bitcoin', value: '$' + price.toLocaleString(), format: 'currency', delta: { value: change, label: change.toFixed(2) + '%' } });"
    }
    ```

    ### Example 4: Page Summarizer Skill (manual trigger)

    User: "Create a page summarizer tool"

    ```json
    {
      "name": "Page Summarizer",
      "description": "Extracts and returns the main text content of the current page",
      "permissions": ["dom.query", "page.read"],
      "triggers": [{ "type": "manual" }],
      "content_script": "const article = wheel.dom.query('article') || wheel.dom.query('main') || wheel.dom.query('body'); wheel.result({ url: wheel.page.url, title: wheel.page.title, content: article ? article.text.substring(0, 5000) : 'No content found' });"
    }
    ```
    """

    private static let rules = """
    1. Output ONLY a valid JSON object, no surrounding text or markdown fences.
    2. Choose the simplest approach: prefer CSS-only over content scripts, content_rules over scripts for blocking.
    3. Scripts must use the wheel.* API — never use raw browser APIs (fetch, localStorage, document.cookie, etc.).
    4. Content scripts run in an isolated world — they cannot access page JavaScript globals.
    5. Background scripts have no DOM access — use wheel.fetch for network, wheel.render for output.
    6. Storage quota is 512KB per module. Network is limited to HTTPS, 10 req/min, 1MB response.
    7. Schedule intervals must be >= 300 seconds (5 minutes).
    8. For ad blockers, use content_rules with 'always' trigger (most efficient, compiled to bytecode).
    9. Permissions must match the APIs used in scripts. Missing permissions cause runtime errors.
    10. Keep scripts concise and focused. One module = one capability.
    """
}
