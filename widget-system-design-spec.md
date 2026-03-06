# LLM Widget System — Implementation Design Spec

**Target:** SwiftUI app with WKWebView fallback  
**Paradigm:** Prompt → Structured Pipeline Spec → Deterministic Execution → Rendered Widget  
**LLM Output Format:** Skill-composition pipeline (typed JSON, never raw code)

---

## 1. Core Mental Model

The LLM never writes code. It writes a **pipeline spec** — a DAG of typed skill invocations that the app executes deterministically. Think of it as: the LLM is a compiler, the skill library is the instruction set, and the app is the CPU.

```
User Prompt
    ↓
[LLM] → WidgetPipelineSpec (JSON)
    ↓
[Validator] → validated spec or repair loop
    ↓
[Executor] → runs steps sequentially, passes data via context dict
    ↓
[Renderer] → SwiftUI view or WKWebView
```

---

## 2. Widget Pipeline Spec Schema

The LLM outputs exactly one JSON object matching this schema. Use your provider's structured output / constrained decoding mode to guarantee compliance.

```json
{
  "$schema": "widget-spec/v1",
  "widget_id": "uuid-v4",
  "title": "Top Posts in r/swift",
  "refresh_interval_seconds": 300,
  "thinking": "...",  // chain-of-thought scratchpad, ignored at runtime
  "pipeline": [
    {
      "id": "step_id_snake_case",
      "skill": "skill_name",
      "params": {
        "key": "value",
        "ref_to_prior_step": "{{other_step_id.output}}"
      }
    }
  ]
}
```

**Rules enforced at validation:**
- `pipeline` must have 1–5 steps
- `skill` must be a value from the skill registry enum
- Variable references use `{{step_id.output}}` syntax; referenced step_id must precede current step
- Last step must be a `render_*` skill
- `refresh_interval_seconds` minimum: 300

### Full JSON Schema (for structured output mode)

```json
{
  "type": "object",
  "required": ["title", "refresh_interval_seconds", "pipeline"],
  "additionalProperties": false,
  "properties": {
    "$schema": { "type": "string" },
    "widget_id": { "type": "string" },
    "title": { "type": "string", "maxLength": 60 },
    "refresh_interval_seconds": { "type": "integer", "minimum": 300 },
    "thinking": { "type": "string" },
    "pipeline": {
      "type": "array",
      "minItems": 1,
      "maxItems": 5,
      "items": {
        "type": "object",
        "required": ["id", "skill", "params"],
        "additionalProperties": false,
        "properties": {
          "id": { "type": "string", "pattern": "^[a-z_]+$" },
          "skill": {
            "type": "string",
            "enum": [
              "fetch_reddit_posts", "fetch_crypto_price_history",
              "fetch_weather", "fetch_rest_api",
              "sort", "filter", "map_fields", "aggregate",
              "render_list", "render_chart", "render_stat_card",
              "render_table", "render_composite"
            ]
          },
          "params": { "type": "object" }
        }
      }
    }
  }
}
```

---

## 3. Skill Library

### 3.1 Data Acquisition Skills

#### `fetch_reddit_posts`
```json
{
  "name": "fetch_reddit_posts",
  "description": "Fetch top/new/hot posts from a subreddit. Use for any Reddit content request.",
  "params": {
    "subreddit": { "type": "string", "description": "Subreddit name without r/ prefix" },
    "sort": { "type": "string", "enum": ["top", "hot", "new", "rising"] },
    "time_range": { "type": "string", "enum": ["hour", "day", "week", "month", "year", "all"] },
    "limit": { "type": "integer", "minimum": 1, "maximum": 25, "default": 10 }
  },
  "output": "Array<{ title, author, score, num_comments, url, created_utc, thumbnail }>"
}
```

#### `fetch_crypto_price_history`
```json
{
  "name": "fetch_crypto_price_history",
  "description": "Fetch OHLCV price history for a cryptocurrency. Use for any price chart or price display.",
  "params": {
    "coin_id": { "type": "string", "description": "CoinGecko coin id, e.g. 'bitcoin', 'ethereum'" },
    "vs_currency": { "type": "string", "default": "usd" },
    "days": { "type": "integer", "enum": [1, 7, 14, 30, 90, 365], "description": "Number of days of history" }
  },
  "output": "Array<{ timestamp_ms, price, volume }>"
}
```

#### `fetch_weather`
```json
{
  "name": "fetch_weather",
  "description": "Fetch current weather and forecast for a location.",
  "params": {
    "location": { "type": "string", "description": "City name or lat,lon" },
    "units": { "type": "string", "enum": ["imperial", "metric"], "default": "imperial" }
  },
  "output": "{ current: { temp, feels_like, humidity, description, icon }, forecast: Array<{ date, high, low, description }> }"
}
```

#### `fetch_rest_api`
```json
{
  "name": "fetch_rest_api",
  "description": "Generic HTTP GET to any public API. Use when no convenience skill exists.",
  "params": {
    "url": { "type": "string", "description": "Full URL. Must be https. No private/internal IPs." },
    "headers": { "type": "object", "description": "Optional HTTP headers as key-value pairs" },
    "query_params": { "type": "object", "description": "Optional query parameters" },
    "json_path": { "type": "string", "description": "Optional dot-notation path to extract from response, e.g. 'data.items'" }
  },
  "output": "Parsed JSON response or extracted subset"
}
```

---

### 3.2 Transform Skills

#### `sort`
```json
{
  "params": {
    "input": { "type": "string", "description": "Variable reference, e.g. {{fetch.output}}" },
    "by": { "type": "string", "description": "Field name to sort by" },
    "order": { "type": "string", "enum": ["asc", "desc"], "default": "desc" }
  }
}
```

#### `filter`
```json
{
  "params": {
    "input": { "type": "string" },
    "field": { "type": "string" },
    "operator": { "type": "string", "enum": ["eq", "neq", "gt", "gte", "lt", "lte", "contains", "not_contains"] },
    "value": { "description": "Comparison value, any scalar type" }
  }
}
```

#### `map_fields`
```json
{
  "description": "Project/rename fields from array of objects. Drop unspecified fields.",
  "params": {
    "input": { "type": "string" },
    "mapping": {
      "type": "object",
      "description": "{ output_field_name: input_field_name_or_template }. Template example: '{{title}} by {{author}}'"
    }
  }
}
```

#### `aggregate`
```json
{
  "params": {
    "input": { "type": "string" },
    "operation": { "type": "string", "enum": ["count", "sum", "avg", "min", "max", "first", "last"] },
    "field": { "type": "string", "description": "Field to aggregate (not needed for count)" },
    "group_by": { "type": "string", "description": "Optional: field to group by before aggregating" }
  }
}
```

---

### 3.3 Render Skills

#### `render_list`
```json
{
  "description": "Renders a scrollable list of items. Maps to native SwiftUI LazyVStack.",
  "params": {
    "data": { "type": "string" },
    "title": { "type": "string" },
    "item_template": {
      "type": "object",
      "properties": {
        "headline": { "type": "string", "description": "Field ref or template string" },
        "subheadline": { "type": "string" },
        "caption": { "type": "string" },
        "badge": { "type": "string", "description": "Short badge text, e.g. score" },
        "link_url": { "type": "string", "description": "Field ref containing URL to open on tap" }
      }
    }
  }
}
```

#### `render_chart`
```json
{
  "description": "Renders a chart in sandboxed WKWebView using Chart.js or Lightweight Charts.",
  "params": {
    "data": { "type": "string" },
    "chart_type": { "type": "string", "enum": ["line", "bar", "area", "candlestick", "scatter", "pie", "doughnut"] },
    "x_field": { "type": "string", "description": "Field name for X axis (or timestamp_ms for time series)" },
    "y_field": { "type": "string", "description": "Field name for Y axis" },
    "title": { "type": "string" },
    "x_label": { "type": "string" },
    "y_label": { "type": "string" },
    "color": { "type": "string", "description": "Hex color for primary series, e.g. '#2196F3'" }
  }
}
```

#### `render_stat_card`
```json
{
  "description": "Renders a single KPI stat card with value, label, and optional delta. Native SwiftUI.",
  "params": {
    "data": { "type": "string", "description": "Single object or scalar" },
    "value_field": { "type": "string" },
    "label": { "type": "string" },
    "delta_field": { "type": "string", "description": "Optional: field for change indicator" },
    "format": { "type": "string", "enum": ["number", "currency", "percent", "temperature", "raw"], "default": "raw" }
  }
}
```

#### `render_table`
```json
{
  "description": "Renders a data grid with sortable columns. Native SwiftUI.",
  "params": {
    "data": { "type": "string" },
    "columns": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "field": { "type": "string" },
          "header": { "type": "string" },
          "width_fraction": { "type": "number", "description": "Column width as fraction of total, e.g. 0.3" }
        }
      }
    },
    "title": { "type": "string" }
  }
}
```

#### `render_composite`
```json
{
  "description": "Compose multiple widget outputs into a layout. Reference render step outputs.",
  "params": {
    "layout": { "type": "string", "enum": ["vstack", "hstack", "grid_2col"] },
    "children": {
      "type": "array",
      "items": { "type": "string", "description": "Variable references to prior render step outputs" }
    },
    "title": { "type": "string" }
  }
}
```

---

## 4. Architecture Layers

### Layer 1: LLM Spec Generator

**Swift interface:**
```swift
protocol WidgetSpecGenerator {
    func generate(prompt: String) async throws -> WidgetPipelineSpec
}
```

**Responsibilities:**
- Build system prompt (see Section 6)
- Call LLM API with structured output mode enabled
- Return decoded `WidgetPipelineSpec` struct
- On failure, pass error to repair loop (max 2 retries)

**Model configuration:**
```swift
struct LLMConfig {
    let model = "claude-sonnet-4-5" // or gpt-4o
    let temperature = 0.0           // deterministic
    let maxTokens = 2048
    let structuredOutputSchema = widgetPipelineJSONSchema
}
```

---

### Layer 2: Validator

```swift
struct SpecValidator {
    func validate(_ spec: WidgetPipelineSpec) throws -> ValidatedSpec
}
```

**Validation passes (in order):**
1. **Schema** — all skill names in allowlist, param types correct (done by structured output, verify anyway)
2. **Reference resolution** — all `{{step_id.output}}` references point to a preceding step
3. **Last step is render** — final pipeline step must be a `render_*` skill
4. **URL allowlist** — any URL in `fetch_rest_api.url` must match curated domain allowlist
5. **Resource limits** — max 5 steps, max 3 data sources, refresh ≥ 300s

**On validation failure**, format an error message and re-prompt:
```
"Your spec has an error in step 2: skill 'fetch_data' is not a valid skill name. 
Valid skills are: [list]. Please regenerate the spec."
```

---

### Layer 3: Pipeline Executor

```swift
struct PipelineExecutor {
    func execute(_ spec: ValidatedSpec) async throws -> RenderInput
}
```

**Execution context:** A simple `[String: Any]` dictionary keyed by step ID.

**Step execution loop:**
```swift
var ctx: [String: Any] = [:]
for step in spec.pipeline {
    let resolvedParams = resolveReferences(step.params, context: ctx)
    let output = try await skillRegistry.execute(skill: step.skill, params: resolvedParams)
    ctx[step.id] = ["output": output]
}
return ctx[spec.pipeline.last!.id]!["output"] as! RenderInput
```

**Reference resolution:** Walk params, replace any string matching `^\{\{(\w+)\.output\}\}$` with `ctx[stepId]["output"]`.

**Skill execution routing:**
- `fetch_*` skills → route through BFF proxy (see Layer 5)
- `sort`, `filter`, `map_fields`, `aggregate` → run in JavaScriptCore sandbox
- `render_*` skills → return structured `RenderInput`, do not execute yet

---

### Layer 4: Renderer

```swift
protocol WidgetRenderer {
    func render(_ input: RenderInput) -> AnyView
}
```

**Routing table:**

| Skill | Renderer | Engine |
|---|---|---|
| `render_list` | `ListWidgetView` | Native SwiftUI |
| `render_stat_card` | `StatCardView` | Native SwiftUI |
| `render_table` | `TableWidgetView` | Native SwiftUI |
| `render_chart` | `ChartWebView` | WKWebView + Chart.js |
| `render_composite` | `CompositeWidgetView` | Mixed |

**`ChartWebView` implementation notes:**
- Bundle Chart.js (`~60KB`) and Lightweight Charts (`~40KB`) in app binary
- Use `WKWebsiteDataStore.nonPersistent()` — ephemeral, no persistence
- Use `WKContentWorld.world(name: "widgets")` — isolated JS namespace
- Inject chart config JSON via `callAsyncJavaScript` after page load
- CSP header: `default-src 'none'; script-src 'nonce-{UUID}'; style-src 'nonce-{UUID}'`
- Communicate events back with: `window.webkit.messageHandlers.widgetBridge.postMessage({...})`
- Auto-size: WKWebView reports content height via postMessage, SwiftUI adjusts frame

---

### Layer 5: BFF Proxy (Backend-for-Frontend)

All external network calls from skills route through this server-side proxy. The app never holds API keys.

**Responsibilities:**
- Credential injection from secrets manager (per-skill API keys)
- Domain allowlist enforcement
- SSRF prevention: resolve DNS, block RFC1918 + loopback + link-local addresses
- Rate limiting per user per skill (e.g., 60 req/min for crypto, 30 req/min for Reddit)
- Response caching (respect `Cache-Control`, minimum 60s TTL for price data)

**BFF skill endpoints:**
```
POST /proxy/fetch_reddit_posts      → Reddit JSON API
POST /proxy/fetch_crypto_price      → CoinGecko API
POST /proxy/fetch_weather           → OpenWeatherMap API
POST /proxy/fetch_rest_api          → Validated external URL
```

**`fetch_rest_api` allowlist** (start conservative, expand over time):
```
api.coingecko.com
www.reddit.com/r/
api.openweathermap.org
api.github.com
hacker-news.firebaseio.com
api.coinbase.com
```

---

### Layer 6: Widget Lifecycle

```swift
struct WidgetInstance {
    let spec: ValidatedSpec
    var lastData: RenderInput?
    var lastFetched: Date?
    var view: AnyView { get }
    
    mutating func refresh() async
}
```

- On app launch: load cached spec + last data snapshot from disk, render immediately
- Schedule background refresh via `BGAppRefreshTask` using `spec.refresh_interval_seconds`
- On foreground: if `lastFetched` is older than `refresh_interval_seconds`, refresh immediately
- Cache: serialize `RenderInput` to JSON on disk per widget_id

---

## 5. Swift Protocol Definitions

```swift
// Core skill protocol
protocol WidgetSkill {
    var name: String { get }
    var jsonSchema: String { get }  // exported to LLM system prompt
    func execute(params: [String: Any]) async throws -> Any
}

// Skill registry
class SkillRegistry {
    private var skills: [String: any WidgetSkill] = [:]
    
    func register(_ skill: any WidgetSkill) { skills[skill.name] = skill }
    func execute(skill: String, params: [String: Any]) async throws -> Any {
        guard let s = skills[skill] else { throw WidgetError.unknownSkill(skill) }
        return try await s.execute(params: params)
    }
    func systemPromptRegistry() -> String {
        skills.values.map { $0.jsonSchema }.joined(separator: "\n\n")
    }
}

// Data models
struct WidgetPipelineSpec: Codable {
    let schema: String?
    let widgetId: String?
    let title: String
    let refreshIntervalSeconds: Int
    let thinking: String?
    let pipeline: [PipelineStep]
}

struct PipelineStep: Codable {
    let id: String
    let skill: String
    let params: [String: AnyCodable]
}

enum WidgetError: Error {
    case unknownSkill(String)
    case invalidReference(String)
    case validationFailed(String)
    case executionFailed(String, underlying: Error)
    case renderFailed(String)
}
```

---

## 6. LLM System Prompt Template

```
You are a widget specification compiler. Your job is to translate a user's 
natural language request into a typed pipeline spec that a Swift app will 
execute to fetch data and render a widget.

## Rules
- You MUST output valid JSON matching the WidgetPipelineSpec schema
- You MUST only use skills from the registry below — never invent skill names
- Data flows between steps via {{step_id.output}} variable references
- The final step MUST be a render_* skill
- Chain-of-thought reasoning goes in the "thinking" field (ignored at runtime)
- Maximum 5 pipeline steps
- refresh_interval_seconds minimum is 300

## Skill Registry
{SKILL_REGISTRY_JSON}

## Output Schema
{WIDGET_PIPELINE_JSON_SCHEMA}

## Examples

### Example 1: Simple list
User: "Show me hot posts from r/programming"
Output:
{
  "title": "Hot Posts in r/programming",
  "refresh_interval_seconds": 300,
  "thinking": "Simple fetch and render. No transform needed.",
  "pipeline": [
    {
      "id": "fetch",
      "skill": "fetch_reddit_posts",
      "params": { "subreddit": "programming", "sort": "hot", "limit": 10 }
    },
    {
      "id": "render",
      "skill": "render_list",
      "params": {
        "data": "{{fetch.output}}",
        "title": "Hot in r/programming",
        "item_template": {
          "headline": "{{title}}",
          "subheadline": "{{score}} pts · {{num_comments}} comments",
          "link_url": "{{url}}"
        }
      }
    }
  ]
}

### Example 2: Multi-step with transform
User: "Bitcoin price chart for the last 24 hours"
Output:
{
  "title": "Bitcoin — Last 24h",
  "refresh_interval_seconds": 300,
  "thinking": "Fetch daily price history, render as area chart.",
  "pipeline": [
    {
      "id": "prices",
      "skill": "fetch_crypto_price_history",
      "params": { "coin_id": "bitcoin", "vs_currency": "usd", "days": 1 }
    },
    {
      "id": "chart",
      "skill": "render_chart",
      "params": {
        "data": "{{prices.output}}",
        "chart_type": "area",
        "x_field": "timestamp_ms",
        "y_field": "price",
        "title": "BTC/USD",
        "y_label": "USD",
        "color": "#F7931A"
      }
    }
  ]
}

### Example 3: Filter + sort
User: "Top 5 links from r/swift with more than 100 upvotes"
Output:
{
  "title": "Top r/swift Links",
  "refresh_interval_seconds": 600,
  "thinking": "Fetch more than needed, filter by score, then sort and take top 5.",
  "pipeline": [
    {
      "id": "fetch",
      "skill": "fetch_reddit_posts",
      "params": { "subreddit": "swift", "sort": "top", "time_range": "week", "limit": 25 }
    },
    {
      "id": "filtered",
      "skill": "filter",
      "params": { "input": "{{fetch.output}}", "field": "score", "operator": "gte", "value": 100 }
    },
    {
      "id": "sorted",
      "skill": "sort",
      "params": { "input": "{{filtered.output}}", "by": "score", "order": "desc" }
    },
    {
      "id": "render",
      "skill": "render_list",
      "params": {
        "data": "{{sorted.output}}",
        "title": "Top r/swift This Week",
        "item_template": {
          "headline": "{{title}}",
          "badge": "{{score}}",
          "subheadline": "u/{{author}}",
          "link_url": "{{url}}"
        }
      }
    }
  ]
}

## Anti-patterns (never do these)
- Do NOT invent skill names like "fetch_data" or "get_posts"  
- Do NOT reference step IDs that haven't appeared yet in the pipeline
- Do NOT put render_* skills anywhere except the final step (unless using render_composite)
- Do NOT add a fetch step after a render step
```

---

## 7. Transform Skill Sandbox (JavaScriptCore)

Transformation steps (`sort`, `filter`, `map_fields`, `aggregate`) run in a `JSContext` with no access to network, DOM, or storage.

```swift
class TransformSandbox {
    private let context = JSContext()!
    
    init() {
        // Disable all dangerous globals
        context.evaluateScript("delete this.XMLHttpRequest; delete this.fetch;")
        
        // Inject the transform runtime (~50 lines of pure JS)
        let runtime = Bundle.main.url(forResource: "transform_runtime", withExtension: "js")!
        context.evaluateScript(try! String(contentsOf: runtime))
    }
    
    func execute(skill: String, params: [String: Any], input: Any) throws -> Any {
        let paramsJSON = try JSONSerialization.data(withJSONObject: params)
        let inputJSON = try JSONSerialization.data(withJSONObject: input)
        let result = context.evaluateScript("""
            widgetTransform('\(skill)', \(paramsJSON), \(inputJSON))
        """)
        // deserialize result back to Swift
    }
}
```

**`transform_runtime.js`** implements `widgetTransform(skill, params, input)` for the four transform skills using only pure JS (Array methods). No dependencies, no `eval`, no dynamic imports.

---

## 8. File / Module Structure

```
WidgetSystem/
├── Spec/
│   ├── WidgetPipelineSpec.swift         // Codable structs
│   ├── SpecValidator.swift              // 5-pass validation
│   └── SpecSchema.json                  // JSON Schema for structured output
├── Skills/
│   ├── SkillRegistry.swift             // Registration + dispatch
│   ├── Acquisition/
│   │   ├── FetchRedditSkill.swift
│   │   ├── FetchCryptoPriceSkill.swift
│   │   ├── FetchWeatherSkill.swift
│   │   └── FetchRestApiSkill.swift
│   ├── Transform/
│   │   ├── TransformSandbox.swift       // JSContext wrapper
│   │   └── transform_runtime.js         // Pure-JS sort/filter/map/aggregate
│   └── Render/
│       ├── RenderInput.swift            // Typed render payloads
│       ├── ListWidgetView.swift
│       ├── StatCardView.swift
│       ├── TableWidgetView.swift
│       ├── ChartWebView.swift           // WKWebView + Chart.js
│       └── CompositeWidgetView.swift
├── Execution/
│   ├── PipelineExecutor.swift
│   ├── BFFClient.swift                  // HTTP client for proxy calls
│   └── ReferenceResolver.swift
├── Generation/
│   ├── WidgetSpecGenerator.swift        // LLM call + repair loop
│   └── SystemPromptBuilder.swift        // Assembles prompt from registry
├── Lifecycle/
│   ├── WidgetInstance.swift
│   └── WidgetStore.swift               // Persistence + refresh scheduling
└── Resources/
    ├── chart.min.js                     // Bundled Chart.js
    └── lightweight-charts.standalone.production.mjs
```

---

## 9. Implementation Order

Build and test each layer before proceeding to the next.

1. **Spec structs + JSON schema** — `WidgetPipelineSpec`, `PipelineStep`, `AnyCodable`, schema file
2. **Skill registry + 2 acquisition skills** — `FetchRedditSkill` + `FetchCryptoPriceSkill` (hardcoded URL, no BFF yet)
3. **Transform sandbox** — `TransformSandbox` + `transform_runtime.js` with `sort` and `filter`
4. **Two native renderers** — `ListWidgetView` + `StatCardView`
5. **Pipeline executor** — wire skills → executor → renderer, test end-to-end with hardcoded spec
6. **Spec validator** — all 5 validation passes
7. **LLM spec generator** — `WidgetSpecGenerator` with system prompt, repair loop
8. **Chart renderer** — `ChartWebView` with WKContentWorld sandboxing
9. **BFF proxy** — move acquisition skills behind proxy, add credential injection
10. **Remaining skills** — `fetch_weather`, `fetch_rest_api`, `map_fields`, `aggregate`, `render_table`, `render_composite`
11. **Widget lifecycle** — `WidgetStore`, disk caching, `BGAppRefreshTask`

---

## 10. Key Constraints & Decisions Summary

| Decision | Choice | Rationale |
|---|---|---|
| LLM output format | Skill-composition JSON pipeline | Best reliability + safety tradeoff |
| Chart rendering | WKWebView + bundled Chart.js | JS charting ecosystem >> Swift Charts |
| Data transforms | JavaScriptCore sandbox | No network/DOM, ships with iOS, zero overhead |
| External API calls | BFF proxy (server-side) | Never expose credentials on-device |
| Native vs web rendering | Native SwiftUI for lists/cards, WKWebView for charts | Native UX where possible |
| LLM temperature | 0.0 | Deterministic spec generation |
| Skill library size | ≤15 skills | Fits in system prompt; larger = LLM confusion |
| Retry on validation failure | Max 2 retries with structured error feedback | Targets >99% valid spec rate |
