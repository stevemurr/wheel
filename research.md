# Wheel Browser — Deep Codebase Research Report

*Generated 2026-03-03 from full source read of all subsystems*

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture Map](#2-architecture-map)
3. [Core Application Layer](#3-core-application-layer)
4. [WebView & Navigation Layer](#4-webview--navigation-layer)
5. [OmniBar System](#5-omnibar-system)
6. [Agent / Browser Automation](#6-agent--browser-automation)
7. [Chat / Letta Conversational AI](#7-chat--letta-conversational-ai)
8. [Semantic Search & DIndex](#8-semantic-search--dindex)
9. [Constellation Visualization](#9-constellation-visualization)
10. [Tab Management & DockTabBar](#10-tab-management--docktabbar)
11. [Ad Blocking & Content Filtering](#11-ad-blocking--content-filtering)
12. [Dark Mode System](#12-dark-mode-system)
13. [History & Fuzzy Search](#13-history--fuzzy-search)
14. [Scraping System](#14-scraping-system)
15. [Widget Pipeline System](#15-widget-pipeline-system)
16. [MCP (Model Context Protocol)](#16-mcp-model-context-protocol)
17. [Workspace & Agent Studio](#17-workspace--agent-studio)
18. [Supporting Subsystems](#18-supporting-subsystems)
19. [Test Suite](#19-test-suite)
20. [Resources & Dependencies](#20-resources--dependencies)
21. [Cross-System Data Flows](#21-cross-system-data-flows)
22. [Architectural Patterns & Conventions](#22-architectural-patterns--conventions)
23. [Issues, Risks & Recommendations](#23-issues-risks--recommendations)
24. [File Inventory](#24-file-inventory)

---

## 1. Project Overview

Wheel is a **macOS-native browser** built with Swift 5.9, SwiftUI, and WebKit. It targets macOS 14+ and ships as a Swift Package Manager executable. Beyond standard browsing, it integrates:

- **AI agent** for autonomous browser automation (ReAct loop with LLM)
- **Conversational chat sidebar** with streaming, thinking display, and artifact rendering
- **Semantic search** via a remote DIndex embedding server
- **Constellation** — a 2D force-directed visualization of browsing history
- **Widget pipeline** — declarative data pipelines (fetch → transform → render) driven by LLM-generated JSON specs
- **MCP server** exposing browser tools to external clients (e.g., Claude Desktop)
- **Ad blocking** with ABP filter list parsing and WebKit content blocker compilation
- **Dark mode injection** with native/filter detection and brightness/contrast controls
- **Headless mode** for off-screen automation with anti-detection scripts

### Package.swift

```
Platform:       macOS 14+
Swift Tools:    5.9
Dependencies:   swift-markdown-ui (2.3+), SwiftSoup (2.6+), DIndexClient (local)
Targets:        WheelBrowser (executable), wheel-mcp-bridge (executable), WheelBrowserTests
Resources:      AppIcon.icns, BlockingRules/, Scripts/, WidgetSystem/
```

### Line Counts (approximate, source only)

| Subsystem | Files | Lines |
|-----------|-------|-------|
| Agent (automation + chat) | ~20 | ~5,300 |
| OmniBar | ~26 | ~3,400 |
| Core (App, ContentView, BrowserState, Tab, WebView) | ~18 | ~3,200 |
| Widget System | ~35 | ~3,000 |
| Ad Blocking | ~8 | ~1,400 |
| Constellation | ~8 | ~1,800 |
| Semantic Search | ~7 | ~1,800 |
| Dark Mode | ~3 | ~760 |
| History | ~2 | ~435 |
| Scraping | ~3 | ~950 |
| Settings | ~8 | ~380 |
| Logging | ~1 | ~450 |
| Misc (Downloads, LinkPreview, Overlay, Services, Shared, MCP, Headless, TopDrawer) | ~20 | ~2,500 |
| **Tests** | **60+** | **~5,000+** |
| **Total** | **~220+** | **~30,000+** |

---

## 2. Architecture Map

```
┌─────────────────────────────────────────────────────────────────────┐
│                        WheelBrowserApp.swift                        │
│    (App entry point, menu commands, keyboard shortcuts, AppDelegate)│
│    30+ Notification.Name → NotificationCenter → ContentView         │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────────────┐
│                         ContentView.swift                           │
│  ┌─────────────┐  ┌───────────────────────┐  ┌──────────────────┐  │
│  │ BrowserState │  │     OmniBar           │  │  Overlay System  │  │
│  │ (tabs, nav)  │  │ (modes, panels, input)│  │ (windows, cards) │  │
│  └──────┬───────┘  └───────────┬───────────┘  └──────────────────┘  │
│         │                      │                                    │
│  ┌──────▼───────┐  ┌──────────▼──────────────────────────────────┐  │
│  │    Tab[]     │  │  Panels (per mode):                         │  │
│  │  ├─ WebView  │  │  ├─ Address → HistoryPanel + SuggestionsVM  │  │
│  │  ├─ title    │  │  ├─ Chat    → ChatOmniPanel (AgentManager)  │  │
│  │  ├─ url      │  │  ├─ Semantic→ SemanticSearchPanel (DIndex)  │  │
│  │  └─ agents   │  │  ├─ Agent  → AgentOmniPanel (AgentEngine)   │  │
│  └──────────────┘  │  ├─ Reading→ ReadingListPanel (SearchDB)    │  │
│                     │  └─ Scrape → ScrapePanelContent             │  │
│                     └────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                        WebView Layer                                 │
│  WebViewRepresentable → Coordinator → {                              │
│     PageLifecycleHandler, NavigationPolicyHandler, DownloadHandler   │
│  }                                                                   │
│  BrowserWebView (custom WKWebView) → ContextMenuBuilder             │
│  AccessibilityBridge (BrowserBridge protocol) → AgentScripts (JS)    │
│  SemanticIndexingHandler → DIndex indexing after page load           │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                     Agent Engine (ReAct Loop)                        │
│  AgentEngine → AgentStreamingClient → LLM (chat/completions API)    │
│  AgentResponseParser ─┬─ Standard format (THOUGHT/ACTION)           │
│                       └─ HarmonyFormatParser (OpenAI structured)     │
│  AgentLoopDetector → recovery strategies (back, scroll, admit)       │
│  AgentPromptBuilder → compressed history + dynamic guidance          │
│  NavigationPolicy → URL validation (no localhost, no file://)        │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                    External Integrations                              │
│  DIndexService (actor) ←→ DIndex server (HTTP + SSE)                 │
│  MCPServer (NWListener) ←→ wheel-mcp-bridge (stdio JSON-RPC)        │
│  LettaClient (actor) ←→ Letta server (optional stateful backend)     │
│  SummaryGenerator (actor) ←→ LLM endpoint (summarization)            │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 3. Core Application Layer

### WheelBrowserApp.swift (~371 lines)

- **@main** entry point. `AppDelegate` handles launch lifecycle: logging setup, ad block rule compilation, app icon, headless mode check.
- 30+ keyboard shortcuts registered via `.keyboardShortcut()` modifiers on menu items.
- All commands dispatched via `NotificationCenter.default.post()` — loose coupling between menu layer and view logic.
- Headless mode creates `HeadlessWindowController` (off-screen window at -10000,-10000).

### ContentView.swift (~441 lines)

Root window layout. Key composition:

```
ContentView
├─ BrowserContentArea (ZStack of all tab WebViews + OmniBar + overlays)
├─ TabWebViewContainer (per-tab, opacity-based visibility)
├─ NavigationErrorOverlay (error display + retry)
├─ Notification modifiers (Tab, Navigation, Zoom handlers)
└─ Constellation overlay (full-screen canvas)
```

- **All tabs rendered in ZStack** — inactive tabs hidden with `.opacity(0)` and `.allowsHitTesting(false)` to preserve JS execution state and enable agent automation on background tabs.
- `@StateObject var state: BrowserState` — single state owner.
- `@State var agentEngine: AgentEngine` — single @Observable instance.
- 8+ shared singletons referenced: agentManager, settings, downloadManager, wheelState, scrapeManager, constellationState, workspaceManager.

### BrowserState.swift (~349 lines)

Centralized tab state manager implementing `ObservableObject` and `BrowserBridgeProvider`.

- **Dual indexing**: `tabs: [Tab]` for ordering + `tabsByID: [UUID: Tab]` for O(1) lookup.
- `closedTabsHistory: [ClosedTabInfo]` — stack of 20 recently closed tabs for undo.
- Workspace integration: `workspaceTabStates: [UUID: WorkspaceTabState]` — in-memory cache (not persisted to disk).
- `assertTabIntegrity()` — debug assertion that arrays stay in sync.

### Tab.swift (~228 lines)

Individual tab model (`Identifiable, ObservableObject`).

- **Lazy WebView creation** — `_webView` private backing, computed `webView` property. Chat-only tabs never allocate a WebView (~30-50MB savings per tab).
- **Lazy controller creation** — `FindInPageController` and `PictureInPictureController` on first use.
- **Per-tab conversation** — `conversationId: UUID` for isolated chat history.
- WebView configured with: dark mode script, link hover detection, anti-detection (headless), cookie banner dismissal, ad blocking rules.
- Zoom range: 0.5x–3.0x in 0.1 steps.

### WindowAccessor.swift (~190 lines)

`NSViewRepresentable` that configures window chrome:
- `isMovableByWindowBackground`, `titlebarAppearsTransparent`, `fullSizeContentView`
- `TrafficLightPillManager` — pill-shaped background behind close/minimize/zoom buttons
- Dark/light mode color switching via `viewDidChangeEffectiveAppearance()`

---

## 4. WebView & Navigation Layer

### WebViewRepresentable.swift (~160 lines)

SwiftUI wrapper with `Coordinator` implementing all WKWebView delegate protocols. Delegates to:
- `NavigationPolicyHandler` — policy decisions (allow/download)
- `DownloadHandler` — download lifecycle
- `PageLifecycleHandler` — load events, dark mode, indexing, screenshots

Popup handling: loads in current webview (returns nil).

### BrowserWebView.swift (~192 lines)

Custom `WKWebView` subclass. Overrides `menu(for:)` to suppress native context menu. Implements JS hit-test flow:
1. Right-click → record coordinates, increment generation counter
2. 200ms safety timeout → fallback menu
3. JS hit-test via `ContextMenuScripts.hitTest()` → `ContextMenuHitTest`
4. `ContextMenuBuilder.buildMenu()` → custom NSMenu

### PageLifecycleHandler.swift (~178 lines)

Manages load lifecycle:
- `didStartProvisionalNavigation` → cancel background tasks, reset error, set loading
- `didCommit` → apply dark mode
- `didFinish` → update UI, record history, index page (DIndex), capture screenshot (0.5s delay)
- Error categorization: maps NSURLError codes → `NavigationError` enum (network, ssl, timeout, hostNotFound, resourceNotFound, serverError, unknown)

### NavigationPolicyHandler.swift (~105 lines)

Decides allow/download for 43 MIME types (office, archives, PDF, media). PDF allowed inline if displayable.

### DownloadHandler.swift (~110 lines)

WKDownload lifecycle with:
- Unique filename generation (appends ` (N)` for collisions)
- KVO progress tracking on `download.progress.fractionCompleted`
- Integration with `DownloadManager.shared`

### ContextMenuBuilder.swift (~210 lines) + ContextMenuScripts.swift (~89 lines)

Custom right-click menu with sections: Link, Image, Media, Editable, Selection, Navigation. JS hit-test walks DOM (including Shadow DOM) to find links, images, media, editable fields.

### LinkHoverScripts.swift (~53 lines)

Injects click listener detecting Cmd+Click on links → posts to `overlayWindow` handler → opens overlay mini-window.

### SemanticIndexingHandler.swift (~99 lines)

After page load: extracts clean text (clone DOM, remove non-content elements, normalize whitespace) → `SemanticSearchManagerV2.indexPage()`. Filters `about:`, `data:`, `javascript:`, `blob:`, `chrome:`, `file:` URLs.

---

## 5. OmniBar System

The OmniBar is the unified input/panel system (~26 files, ~3,400 lines). It implements a multi-mode pill with mutually exclusive panels.

### Modes & Panels

```
OmniBarMode enum: .address | .chat | .semantic | .agent | .readingList | .scraping
OmniBarPanelVisibility: mutually exclusive panel visibility
```

### OmniBar.swift (~324 lines) — Main View

Composition:
```
OmniBar body → VStack
├─ panelViews (@ViewBuilder, mode-specific panels)
├─ mentionDropdownPanel (@ trigger in chat)
├─ find bar (Group, isolated animation)
└─ omniBarContent (HStack, implicit .animation() on shouldExpand)
    ├─ navigationButtons (back/forward/reload)
    ├─ inputPill
    │   ├─ modeIndicator (icon, cycles modes on click)
    │   ├─ mentionChips (chat mode)
    │   ├─ OmniBarTextField (single-line) / OmniBarTextEditor (multi-line, chat)
    │   └─ actionButton (mode-specific: search, send, stop, etc.)
    ├─ panel toggle buttons (chat, semantic, agent, reading list)
    ├─ saved indicator
    └─ zoom indicator
```

### Animation Invariant System (13 Rules)

The OmniBar has a documented 13-rule animation invariant system (in CLAUDE.md) to prevent flash/flicker:

| # | Rule | Why |
|---|------|-----|
| 1 | No `.animation()` on parent VStack | Two overlapping contexts → flash |
| 2 | No `withAnimation` in mode setters | Nested contexts → flash |
| 3 | No dismiss-then-activate in `handleModeChange` | Two sequential `withAnimation` → flash |
| 4 | Guard delayed dismissals against stale focus | 200ms delay checks `isInputFocused` |
| 5 | No `.contentTransition(.opacity)` on streaming | High-frequency + opacity → flash |
| 6 | `@Observable` classes as plain `var` | Per-property tracking, minimal re-evals |
| 7 | No redundant `setVisiblePanel` calls | Guard prevents duplicates |
| 8 | Non-animated state BEFORE animated panel | `@Published` fires before transition |
| 9 | Set focus BEFORE mode | Prevents dismiss-then-show |
| 10 | No dead `@Published` properties | Fires `objectWillChange` → full re-eval |
| 11 | No `withAnimation` on `isInputFocused = true` | Conflicts with pill expansion |
| 12 | Only `shouldExpand` in animation state | Prevents redundant animation triggers |
| 13 | Extract sub-views for `@Observable` data sources | Isolates high-frequency updates |

9 extracted sub-views enforce Rule 13: `ChatPanelToggle`, `AgentPanelToggle`, `ModeIndicatorView`, `AgentActionButton`, `ChatModeActionButton`, `AgentInlineStatusView`, `ChatOmniPanel`, `AgentOmniPanel`, `OmniBarNotificationModifier`.

### Event Handler Pipeline (OmniBarEventHandlers.swift, ~456 lines)

**Mode change flow:**
```
setMode() → @Published mode change → onChange(of: mode)
  → handleModeChange()
    → clearSearchState(except: newMode)
    → updateFullPageChatState()
    → guard isInputFocused
    → activateMode(newMode)
      → load non-animated state first (suggestions, search results)
      → setVisiblePanel() [animated] last
```

**Focus management:**
- `handleFocusGained()` → `activateMode(isFocusGain: true)`
- `handleFocusLost()` → 200ms delay, guard `isInputFocused`, dismiss panel
- Focus handler methods: set `isInputFocused = true` BEFORE `setMode()` (Rule 9)

**Escape priority:** Stop streaming → dismiss downloads → dismiss mention dropdown → hide find bar → dismiss panel → defocus input.

### Input Components

- **OmniBarTextField.swift** (~157 lines): `NSViewRepresentable` wrapping `NSTextField`. Disables macOS text completion. Handles @ trigger detection.
- **OmniBarTextEditor.swift** (~261 lines): `NSViewRepresentable` wrapping `NSTextView` in `NSScrollView`. Auto-resizes 1-6 lines. Custom `ChatTextView` intercepts Enter (submit) vs Shift+Enter (newline). Async focus retry.

### Suggestion ViewModels

- **SuggestionsViewModel** (~270 lines): Address bar history + open tabs. 50ms debounce. Up to 20 results. Scoring: exact (1000), tabs (1100), fuzzy.
- **SemanticSearchViewModel** (~59 lines): 300ms debounce. DIndex search with category filtering.
- **MentionSuggestionsViewModel** (~296 lines): @ trigger suggestions. 30ms debounce. Sources: current page, history, web, reading list, tabs, overlays, semantic. Max 10.
- **ReadingListViewModel** (~110 lines): 150ms debounce. Up to 100 pages from `SearchDatabase`.

### Mentions System

- `Mention` enum: `.currentPage`, `.tab(id,title,url)`, `.overlay(...)`, `.semanticResult(...)`, `.history`, `.web`, `.readingList`, `.domain(String)`
- Persistent mentions (`@web`, `@history`, `@readingList`) survive mode switches
- `MentionContentResolver` extracts content from mentioned pages for agent context

---

## 6. Agent / Browser Automation

The Agent is a **ReAct loop** (~13 files, ~4,500 lines) that autonomously performs web tasks.

### AgentEngine.swift (~866 lines) — Main Orchestrator

`@Observable, @MainActor` class. Core loop:

```
run(task) → [loop: iteration < maxSteps && elapsed < timeout]
  1. OBSERVE: AccessibilityBridge.snapshot() → PageSnapshot
     - JS collects 28 element types, filters visible, caps at 40
     - Detects 5 captcha types (reCAPTCHA, hCaptcha, Cloudflare, Turnstile, text)
     - Extracts headings (h1-h3), content summary (1500 chars)
  2. THINK: callLLMWithStreaming(prompt, systemPrompt)
     - AgentPromptBuilder: task + page state + compressed history
     - AgentStreamingClient: SSE stream, extracts THOUGHT for live UI
  3. PARSE: AgentResponseParser.parseResponse()
     - Standard format: THOUGHT: ... ACTION: ...
     - Fallback: HarmonyFormatParser for <|message|> structured output
     - Fallback: AgentReasoningExtractor for reasoning_content
  4. ACT: executeAction(action, bridge)
     - Re-validate element (SPA re-renders)
     - Capture pre-action state → execute → compute ActionDelta
     - Adaptive delays: URL change → waitForLoad, DOM change → 300ms, else 100ms
  5. DETECT LOOPS: AgentLoopDetector
     - Same action 4x, oscillating A-B-A-B, click loops, scroll loops, 3-cycles
     - Recovery: go back → scroll down → admit failure (max 2 attempts)
  6. POST-DONE VERIFICATION
     - Checks for 404, captcha, blank page (<4 elements)
     - Rejects premature done() (max 2 rejections)
```

**Guardrails:** 50 steps max, 300s timeout, warnings at 80% thresholds.

### 16 Browser Actions

| Action | Implementation |
|--------|----------------|
| `click(id[, modifiers])` | JS MouseEvent dispatch with shift/meta/ctrl/alt |
| `type(id, "text")` | Clear + set value + fire input/change events |
| `press_enter` | Dispatch keydown/keypress/keyup (code 13) + form.requestSubmit() |
| `scroll(up/down/top/bottom)` | window.scrollBy/scrollTo with smooth behavior |
| `navigate(url)` | URL validation (NavigationPolicy) + tab.load() |
| `back()` | tab.goBack() |
| `wait_for_user(reason)` | Poll for URL/DOM/captcha changes (120s max) |
| `wait(seconds)` | Task.sleep |
| `read_text(id)` | JS text extraction near element (2000 char limit) |
| `read_links` | All `<a href>` deduplicated, 50 link cap |
| `extract_content` | ContentExtractor (4000 char limit) |
| `scrape(url, depth, maxPages)` | Background ScrapeManager job |
| `new_tab` | BrowserState.addTab() |
| `open_tab(url)` | BrowserState.addTab(withURL:) |
| `switch_tab(index)` | BrowserState.selectTab() + rebind agent |
| `done(summary)` | Mark task complete |

### Security Guardrails

- **NavigationPolicy.swift** (~99 lines): Blocks `file:`, `javascript:`, `data:`, `blob:`, `about:` schemes. Blocks localhost, `127.0.0.1`, `169.254.169.254` (AWS metadata), private IPs.
- **AgentInputValidator.swift** (~50 lines): Max 10,000 chars, rejects `<script`, `eval(`, `innerHTML`, etc.

### Protocol-Based Design

```swift
protocol BrowserBridge {  // Enables mock testing
    func snapshot() -> PageSnapshot
    func click(elementId:, modifiers:)
    func type(elementId:, text:)
    func pressEnter()
    func scroll(deltaX:, deltaY:)
    func waitForLoad(timeout:, stableThreshold:)
    func revalidateElement(id:, tag:, text:) -> Int
    ...
}

protocol BrowserBridgeProvider {
    func bridge(for tabId: UUID) -> BrowserBridge?
}
```

`AccessibilityBridge` (~402 lines) implements `BrowserBridge` via JavaScript injection into WKWebView.
`AgentScripts.swift` (~552 lines) centralizes all agent JavaScript.

---

## 7. Chat / Letta Conversational AI

### AgentManager.swift (~597 lines)

`@Observable, @MainActor` singleton for multi-turn conversational AI (distinct from AgentEngine automation).

- **Per-tab conversation snapshots**: caches messages per `conversationId`, switches on tab change.
- **Streaming orchestration**:
  1. Add assistant placeholder with `isStreaming: true`
  2. Iterate chunks from SSE stream
  3. Accumulate thinking → flush at markdown boundaries (max 200 chars or 50ms)
  4. Accumulate content → flush at boundaries
  5. On finish: parse follow-up suggestions `[SUGGESTIONS]...[/SUGGESTIONS]`, extract artifacts
- **Follow-up suggestions**: up to 3 parsed from model output, displayed as clickable pills.
- **Message operations**: send, retry failed, stop generation, edit + resend, regenerate, clear.

### Letta Subsystem (~6 files, ~800 lines)

Optional backend for stateful, long-context conversations:

- **LettaClient** (actor): HTTP client for Letta server API — agent CRUD, messaging, archival memory, health check.
- **LettaModels**: Data models (LettaAgent, LettaMessage, StreamingChunk, FunctionCallInfo, ArchivalMemoryEntry).
- **StreamingResponseProcessor** (~70 lines): Parses SSE events into typed chunks (Content, Thinking, FinishReason). Provider-agnostic (Claude `delta.thinking`, OpenAI `delta.reasoning_content`).
- **ConversationHistoryBuilder** (~75 lines): Assembles system prompt + conversation history + page contexts.
- **MarkdownBufferFlusher** (~19 lines): Detects natural markdown boundaries for streaming flush points.

---

## 8. Semantic Search & DIndex

### DIndexService.swift (~354 lines)

Actor wrapping the remote DIndex server:
- `indexPage()`: Index content with embedding categories
- `search()`: Semantic search with optional category filtering
- `clusterDocuments()`: Semantic clustering for Constellation
- `startScrape()/cancelScrape()/subscribeScrapeEvents()`: SSE-based scrape orchestration
- **Exponential backoff**: 3 attempts, 0.5-8s delay, retries 5xx, fails immediately on 4xx.

### SemanticSearchManagerV2.swift (~378 lines)

`@MainActor, ObservableObject` coordinator:
- Manages DIndex health checking and auto-reinitialization on settings changes
- Converts `DIndexSearchItem` → `SemanticSearchResult` with multi-chunk citations
- Publishes: `isIndexing`, `indexedCount`, `isDIndexConnected`, `lastError`
- Falls back to BrowsingHistory fuzzy search if DIndex unavailable.

### SearchDatabase.swift (~590 lines)

Actor wrapping SQLite for reading list + page metadata:
- Schema: `pages` table + FTS5 virtual table for full-text search
- WAL mode, NORMAL sync, foreign key support
- **Graceful degradation**: falls back to in-memory DB if on-disk fails
- Prunes old content, validates integrity on startup
- Operations: `upsertPage()`, `toggleSaved()`, `searchSavedPages()`, `updateSummary()`

---

## 9. Constellation Visualization

Interactive 2D canvas visualization (~8 files, ~1,800 lines) of browsing history as clustered dot nodes.

### Two-Phase Clustering

1. **Phase 1 (immediate)**: `ConstellationClusterer.clusterByDomain()` — O(n) grouping
2. **Phase 2 (async)**: `ConstellationClusterer.clusterFromDIndex()` — semantic clusters from DIndex server (silent failure → stays on domain clusters)

### Force-Directed Layout (~184 lines)

- 150 iterations of force simulation:
  - **Repulsion**: All-pair O(n²) with 1/r falloff and jitter for coincident nodes
  - **Attraction**: Chain links within clusters (O(k) per cluster)
  - **Center pull**: Soft gravity toward canvas center
- Post-normalization: scale non-fixed nodes to fill canvas (60px margins)
- User-dragged positions are "fixed" — never recomputed during simulation
- Runs on background thread via `Task.detached`

### Canvas Interactions

- **Pan**: minimum 5pt drag, blocked during card drag
- **Pinch zoom**: clamped [0.3, 3.0], center-anchor
- **Scroll-wheel zoom**: cursor-aware (preserves point under cursor)
- **Card drag**: saves position on release (history mode only)
- **Hover card**: screen-space at constant size (unaffected by zoom)
- **Cluster labels**: 8-iteration overlap-resolution algorithm
- **Persistence**: per-workspace JSON, max 500 positions with recency pruning

---

## 10. Tab Management & DockTabBar

### StageManagerStrip.swift (~174 lines)

Left-side tab strip with two states:
- **Collapsed**: thin colored binder tabs (8-14px) per tab, color-coded by domain
- **Expanded** (on hover): full 3D thumbnails slide in with `panelSpring` animation
- Collapse delayed 350ms to prevent flicker on brief cursor exits.

### StageManagerThumbnail.swift (~184 lines)

110x70px thumbnails with:
- 3D Y-axis tilt (8 degrees)
- Screenshot or placeholder gradient
- Title overlay with dark fade
- Hover-reveal close button
- Active/agent/inactive border styling

### Tab Wheel (RightClickPanel)

Circular tab switcher activated on right-click:
- **TabWheelState** (~112 lines): Manages rotation, scroll accumulation, selected index. Scroll threshold: 20px trackpad, 1px mouse wheel.
- **TabWheelView** (~170 lines): Dynamic radius (130-200px based on tab count). Depth-sorted, front tab at 1.3x scale, back at 0.35x. Rotation caching (5 degree threshold).
- **RightClickPanelContainer** (~203 lines): Scroll interceptor + click-outside detector (circular hit-test).

---

## 11. Ad Blocking & Content Filtering

### Architecture (~8 files, ~1,400 lines)

```
ABP filter list text
  → ABPParser (actor) → ABPRule[]
    → WebKitRuleConverter → WebKit Content Blocker JSON
      → ContentBlockerManager → WKContentRuleList (compiled per source)
```

### Built-in Categories

| Category | File | Description |
|----------|------|-------------|
| ads | ads.json | Ad domains, Google Ads, DoubleClick, etc. |
| trackers | trackers.json | Tracking pixels, analytics |
| socialWidgets | social.json | Social media trackers |
| annoyances | annoyances.json | Popups, notifications, cookie banners |

### External Filter Lists

- `FilterListManager`: subscription management with concurrent updates
- `FilterListFetcher`: HTTP conditional requests (ETag/If-Modified-Since), SHA256 checksums
- Default lists: EasyList (enabled), EasyPrivacy (disabled), Fanboy's Annoyance (disabled)
- Max 50,000 rules per list

### Cookie Banner Dismissal

Three-layer approach:
1. CSS `display:none` rules in blocking JSON
2. CMP-specific handlers (OneTrust, Cookiebot, TrustArc, Quantcast, Didomi, Usercentrics, Klaro, Sourcepoint) calling platform APIs
3. Generic MutationObserver + button text matching fallback (5 languages: EN, DE, FR, ES, IT)

---

## 12. Dark Mode System

### Three-File Architecture (~760 lines)

- **DarkModeManager** (~167 lines): Coordinates state, observes system appearance for auto mode, injects scripts
- **DarkModeCSS** (~110 lines): Generates CSS with configurable brightness/contrast
- **DarkModeScripts** (~485 lines): Complete JS bundle with detection, injection, runtime API

### Detection & Application

1. **Native mode**: Set `color-scheme: dark` for sites with native dark mode
2. **Filter mode**: Apply `invert(1) hue-rotate(180deg) brightness(B) contrast(C)` with selective un-invert for images/video/canvas/iframes
3. **Background detection**: Check computed luminance of body/html background (threshold < 0.4 = dark)

### Runtime API (exposed via `window.__wheelDarkMode`)

```javascript
enable(), disable(), toggle()
isActive() → Boolean
getMode() → "native" | "filter"
forceFilterMode()
updateCSS(newCSS)
```

Mutation observer watches for style element removal and re-injects.

---

## 13. History & Fuzzy Search

### BrowsingHistory.swift (~270 lines)

`@MainActor ObservableObject` singleton:
- URL index dictionary for O(1) duplicate detection
- Debounced persistence (2s batches) to `history.json`
- Max 1000 entries with overflow trimming
- Workspace-aware filtering
- Corruption recovery with timestamped backups

### FuzzySearch.swift (~165 lines)

Scoring algorithm:
- Exact match: 1000pts
- Prefix match: 800pts
- Separator-adjacent: 700pts
- Substring: 600pts
- Fuzzy per-char: 5pts + bonuses (string start +20, separator +15, word boundary +12, camelCase +10)
- Consecutive match bonus: logarithmic growth
- Gap penalty: 2.0 * log2(distance)
- Match ratio bonus: up to 50pts

Dual-source matching: scores both title and URL independently, takes best.

---

## 14. Scraping System

### ScrapeManager.swift (~358 lines)

`@MainActor, ObservableObject` managing scrape jobs:

- Calls `DIndexService.startScrape()` → creates `ScrapeJob` → subscribes to SSE
- Handles events: `jobStarted`, `urlQueued`, `urlFetching`, `urlIndexed`, `urlFailed`, `urlSkipped`, `progress`, `jobCompleted`, `lagged`
- Per-URL progress tracking with status, title, chunks, duration, error
- Rate/ETA calculation from progress events

### ScrapeConfigSheet.swift (~203 lines)

Modal for scrape parameters: depth (0-3), domain toggle, max pages slider (10-500).

---

## 15. Widget Pipeline System

Declarative data pipeline system (~35 files, ~3,000 lines). LLM generates JSON specs, app executes deterministically.

### Architecture

```
WidgetPipelineSpec (JSON DAG)
  → PipelineExecutor (actor)
    → Step 1: Acquisition skill (FetchRedditSkill, FetchCryptoPriceSkill, ...)
    → Step 2: Transform skill (SortSkill, FilterSkill, MapFieldsSkill, ...)
    → Step 3: Render skill (RenderListSkill, RenderTableSkill, RenderChartSkill, ...)
  → RenderInput → SwiftUI view
```

### Skills (13 total)

| Category | Skills |
|----------|--------|
| **Acquisition** (4) | FetchRedditSkill, FetchCryptoPriceSkill, FetchWeatherSkill, FetchRestApiSkill |
| **Transform** (4) | SortSkill, FilterSkill, MapFieldsSkill, AggregateSkill |
| **Render** (5) | RenderListSkill, RenderStatCardSkill, RenderChartSkill, RenderTableSkill, RenderCompositeSkill |

### Execution

- Steps reference outputs via `{{step_id.output}}`
- 30s timeout per step
- `AnyCodable` for flexible parameters
- `SpecSchema.json` for validation
- `transform_runtime.js` for JS-based transforms
- `chart.umd.min.js` for Chart.js rendering

---

## 16. MCP (Model Context Protocol)

Two-tier architecture for external browser control:

### MCPServer (~200 lines, in-process)

- `NWListener` on port 8765, localhost-only
- HTTP request parsing with per-connection buffer accumulation
- 9 browser tools exposed:

| Tool | Purpose |
|------|---------|
| `browser_snapshot` | Get interactive element list |
| `browser_click` | Click element by ID |
| `browser_type` | Type text into element |
| `browser_scroll` | Scroll page |
| `browser_navigate` | Navigate to URL |
| `browser_status` | Get tab list + active tab |
| `agent_run` | Run autonomous agent task |
| `agent_cancel` | Cancel running agent |

### wheel-mcp-bridge (~309 lines, separate binary)

Stdio JSON-RPC bridge:
- Reads newline-delimited JSON from stdin
- Handles locally: `initialize`, `tools/list`
- Forwards to browser: `tools/call` → HTTP POST to localhost:8765
- Writes JSON-RPC response to stdout
- `DispatchSemaphore`-based blocking for async HTTP responses

---

## 17. Workspace & Agent Studio

### Workspace System (~387 lines)

- **Workspace**: Codable struct with name, icon (20 SF Symbols), color (10 presets), tab IDs, optional default agent
- **WorkspaceManager**: CRUD + switching, tab state persistence, creates "Default" workspace if none exist
- Persistence: `workspaces.json` + `workspace_tabs.json`

### Agent Studio (~302 lines)

- **AgentConfig**: name, icon (30 presets), soul (system prompt), model (6 presets), skills (6: web research, summarization, code assist, form filling, price comparison, fact checking)
- **AgentStudioManager**: CRUD + active agent selection, ensures always >=1 agent and >=1 default
- Persistence: `agents.json`

---

## 18. Supporting Subsystems

### Logging (Log.swift, ~451 lines)

Unified structured logging with pluggable sinks:
- **ConsoleSink**: stdout with optional emoji and timestamps
- **OSLogSink**: Darwin os.log with lazy per-category Logger instances
- **FileSink**: Append-only with NSLock for thread safety
- **24 categories**: agent, adBlock, browser, chat, core, darkMode, downloads, history, linkPreview, omniBar, overlay, widgets, search, services, mcp, settings, newTabPage, scrape, screenshot, tabs, workspace, etc.

### Downloads (DownloadManager.swift)

- `DownloadItem`: filename, url, destination, progress, status (downloading/completed/failed/cancelled)
- Shared singleton with `@Published` downloads array
- KVO progress tracking per download

### LinkPreview (~320 lines)

Summary window with content fetching:
- Title extraction: og:title → `<title>` fallback
- Content cleaning: strip scripts/styles/tags, decode HTML entities
- Summarization: streaming via `SummaryGenerator` → fallback to 300-char snippet
- Side effect: indexes page in DIndex (background)

### OverlayWindowManager

Floating window management: max 5 windows, cascade positioning, z-ordering, minimize/maximize.

### Services (SummaryGenerator, ~100 lines)

Actor-based LLM summarization: 3000-char content truncation, 256 max tokens, temperature 0.3, streaming SSE.

### Shared Utilities

| File | Purpose |
|------|---------|
| AsyncRetry.swift (~85 lines) | Exponential backoff (configurable max attempts, delay, retry filter) |
| Debouncer.swift (~28 lines) | Actor-based debouncing with cancel-and-replace |
| JavaScriptEscaper.swift (~38 lines) | Safe string escaping for JS injection |
| SSEParser.swift (~40 lines) | AsyncSequence for SSE "data: " lines |
| PasteboardHelper.swift (~18 lines) | Clipboard copy operations |
| LLMClient.swift (~100 lines) | Protocol for unified LLM interactions (complete, stream) |
| ChatMessage.swift (~100 lines) | Unified chat message model with artifacts, branching, thinking |
| PersistableManager.swift (~134 lines) | Protocol + mixin for JSON persistence with debounced saves (500ms) |
| AppContainer.swift (~46 lines) | Dependency injection container for core services |

### Headless Mode (~241 lines)

- **HeadlessConfig**: CLI parser (`--headless`, `--url`, `--port`, `--window-size`)
- **AntiDetectionScripts**: Spoofs visibility API, WebDriver flag, permissions, plugins, languages, performance timing jitter
- **HeadlessWindowController**: Off-screen NSWindow at (-10000, -10000) hosting minimal SwiftUI + MCPServer

### Content Extraction (ContentExtractor.swift, ~104 lines)

Extracts clean text from web pages via JS DOM cloning:
- Remove script, style, noscript, iframe, nav, header, footer, aside, ad-like elements
- Find main content via `<main>`, `<article>`, `[role="main"]`, `.content`, `.post`
- Truncate to 4000 chars (sentence boundary preferred, word boundary fallback)

---

## 19. Test Suite

**60+ test files, 350+ tests** using Swift Testing framework (`@Suite`, `@Test` macros).

### Coverage by Subsystem

| Category | Files | Tests | Key Coverage |
|----------|-------|-------|--------------|
| Agent | 7 | ~50 | Response parsing (27 tests for 15 action types), page snapshot delta, live LLM tests |
| Widget System | 16+ | ~80 | Pipeline execution, transform sandbox, render skills, schema validation |
| Ad Blocking | 2 | ~34 | ABP parser, WebKit rule converter (ABP tests have pre-existing crash) |
| Constellation | 2 | ~19 | Domain clustering, DIndex clustering, force layout properties |
| Utilities | 5 | ~40 | JS escaping (18), debouncer (8), URL formatter, relative time, fuzzy search (20) |
| History | 2 | ~20 | Entry management, search, workspace filtering |
| LLM | 2 | ~15 | Action parsing, loop detection (cycles, oscillation, custom thresholds) |
| Workspace | 2 | ~10 | Data models, manager lifecycle |
| Letta/Settings | 2 | ~10 | Streaming processor, keychain |

### Test Infrastructure

| Helper | Purpose |
|--------|---------|
| MockLLMClient | Scripted LLM responses, per-character streaming simulation |
| MockBrowserBridge | Records all actions, returns preset snapshots |
| AgentTestRunner | Orchestrates scenario → engine → result evaluation |
| AgentTestReporter | Formats results as reports + JSON |
| AgentTestScenario | JSON fixture loader with tags, success criteria |
| PageSnapshotFactory | Factory for test page snapshots |
| TestableBrowsingHistory | In-memory history (no disk I/O) |
| MockWidgetSkill | Mock skill execution |

### Known Test Issues

- **ABPParserTests**: Pre-existing crash (index out of range) — skip with `--skip "ABPParser"`
- **AgentLiveTests**: Require network + LLM server — skip with `--skip "AgentLiveTests"`

### Run Commands

```bash
cd WheelBrowser && swift test
# Skip flaky:
swift test --skip "AgentLiveTests" --skip "ABPParser"
```

---

## 20. Resources & Dependencies

### Bundled Resources

| Resource | Type | Purpose |
|----------|------|---------|
| `AppIcon.icns` | macOS icon | App icon |
| `BlockingRules/ads.json` | WebKit rules | Ad blocking |
| `BlockingRules/trackers.json` | WebKit rules | Tracker blocking |
| `BlockingRules/social.json` | WebKit rules | Social widget blocking |
| `BlockingRules/annoyances.json` | WebKit rules | Annoyance blocking |
| `Scripts/cookie-banner-dismissal.js` | JavaScript (~405 lines) | CMP dismissal (8 CMPs, 5 languages) |
| `WidgetSystem/SpecSchema.json` | JSON Schema | Widget spec validation |
| `WidgetSystem/transform_runtime.js` | JavaScript | Transform skill sandbox |
| `WidgetSystem/chart.umd.min.js` | JavaScript (minified) | Chart.js for rendering |

### External Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| swift-markdown-ui | 2.3+ | Markdown rendering in chat |
| SwiftSoup | 2.6+ | HTML parsing |
| DIndexClient | local | DIndex server HTTP client |

### Transitive Dependencies (via .build)

- NetworkImage — async image loading
- swift-cmark — CommonMark parsing (for MarkdownUI)
- Grape/ForceSimulation — force-directed graph (for Constellation)
- swift-atomics — atomic operations
- LRUCache — cache data structure

---

## 21. Cross-System Data Flows

### Page Load → Indexing → Search

```
User navigates to URL
  → Tab.load() → WKWebView.load()
    → PageLifecycleHandler.didFinish()
      → Record in BrowsingHistory
      → SemanticIndexingHandler.indexPage()
        → Extract text via JS DOM clone
        → SemanticSearchManagerV2.indexPage()
          → DIndexService.indexPage() (remote embedding)
    → Capture screenshot (0.5s delay)
    → Apply dark mode if enabled
```

### Agent Automation → MCP

```
External client (Claude Desktop)
  → wheel-mcp-bridge (stdin JSON-RPC)
    → HTTP POST to MCPServer (localhost:8765)
      → MCPServer.handleToolCall()
        → AgentEngine.runTask() or direct browser actions
          → AccessibilityBridge → WKWebView JavaScript
```

### Chat Message → Context Resolution

```
User types message with @mentions in OmniBar
  → handleSubmit()
    → MentionContentResolver.resolve(mentions)
      → ContentExtractor.extractContent() for each mentioned page
    → AgentManager.sendMessage(content, pageContexts)
      → ConversationHistoryBuilder.buildFullMessage()
      → streamLLM() → SSE stream → StreamingResponseProcessor
      → Parse follow-ups, extract artifacts
```

### Constellation Load

```
User opens Constellation
  → Phase 1: BrowsingHistory.entries → ConstellationNode[] (max 200)
    → ConstellationClusterer.clusterByDomain() [O(n)]
    → ConstellationLayout.layout() [background, 150 iterations]
    → Display dots with domain colors
  → Phase 2 (async): DIndexService.clusterDocuments() [remote]
    → ConstellationClusterer.clusterFromDIndex() [semantic]
    → Re-layout with semantic clusters [animated]
```

### Widget Pipeline

```
LLM generates WidgetPipelineSpec JSON
  → SpecValidator validates against SpecSchema.json
  → PipelineExecutor resolves step references {{step_id.output}}
    → Acquisition skill (HTTP fetch)
    → Transform skill (sort/filter/map/aggregate via JS sandbox)
    → Render skill → RenderInput (list/table/chart/stat/composite)
  → SwiftUI renders RenderInput
  → Cached for refreshIntervalSeconds (min 300s)
```

### Scraping Flow

```
User clicks "Scrape Page" → ScrapeConfigSheet
  → ScrapeManager.startScrape()
    → DIndexService.startScrape() (remote)
    → Subscribe to SSE event stream
    → Events: jobStarted → urlQueued → urlFetching → urlIndexed → jobCompleted
    → UI updates in real-time (ScrapePanelContent)
    → On completion: refresh SemanticSearchManagerV2.stats
```

---

## 22. Architectural Patterns & Conventions

### State Management

| Pattern | Usage |
|---------|-------|
| `@Observable` (Observation framework) | AgentEngine, AgentManager — per-property tracking, minimal redraws |
| `ObservableObject` (`Combine`) | BrowserState, OmniBarState, ScrapeManager — full `objectWillChange` |
| `@StateObject` / `@ObservedObject` | View-level state ownership |
| `@AppStorage` | Settings persistence via UserDefaults |
| Actor isolation | DIndexService, SearchDatabase, SummaryGenerator, LettaClient, Debouncer |
| `@MainActor` | All UI-touching managers |
| Singletons | AppSettings.shared, WorkspaceManager.shared, ConstellationState.shared, etc. |

### Persistence Strategy

| Data | Storage | Method |
|------|---------|--------|
| Settings | UserDefaults | `@AppStorage` |
| API keys | macOS Keychain | `KeychainHelper` |
| History | `~/Library/Application Support/WheelBrowser/history.json` | Debounced JSON (2s) |
| Reading list | SQLite (WAL mode) | SearchDatabase actor |
| Workspaces | `workspaces.json` + `workspace_tabs.json` | Debounced JSON (500ms) |
| Agents | `agents.json` | Debounced JSON (500ms) |
| Constellation positions | Per-workspace JSON | On position save |
| Filter lists | `FilterLists/` directory | Per-list JSON cached |
| Ad block rules | WebKit compiled rules | In-memory cache |

### Error Handling Patterns

- `LocalizedError` enums with descriptive messages throughout
- Exponential backoff for transient errors (DIndex, LLM)
- Silent logging for non-critical failures (dark mode, indexing)
- Corruption recovery with timestamped backups (history)
- Graceful degradation (DIndex unavailable → fuzzy search fallback)

### JavaScript Bridge Pattern

1. Swift generates JavaScript string (via static lets/funcs in `*Scripts.swift`)
2. Text escaped via `JavaScriptEscaper.escape()`
3. Executed via `webView.evaluateJavaScript()`
4. JS returns JSON object → Swift decodes via `as? [String: Any]`
5. Errors thrown as typed enum cases / logged

---

## 23. Issues, Risks & Recommendations

### Critical

| Issue | Location | Impact | Recommendation |
|-------|----------|--------|----------------|
| O(n^2) repulsion in Constellation layout | ConstellationLayout.swift | ~4.5s for 200 nodes | Quadtree spatial partitioning (O(n log n)) |
| No thread safety annotations | BrowserState, multiple managers | Race conditions possible | Add `@MainActor` to all UI-touching code |
| Workspace tab state not persisted to disk | BrowserState.workspaceTabStates | Lost on app restart | Save/load from disk on workspace switch |
| DIndex single point of failure | SemanticSearch subsystem | Entire semantic search fails if unreachable | Local embedding model fallback |

### High

| Issue | Location | Impact |
|-------|----------|--------|
| Agent done() verification incomplete | AgentEngine | May call done() on login pages, redirect loops, JS errors |
| Screenshot capture on every tab switch | BrowserState.selectTab() | Performance bottleneck on frequent switching |
| Loop detection suppressed while visiting new URLs | AgentLoopDetector | Agent may loop longer on multi-page tasks |
| MCP no authentication | MCPServer | Any local process can invoke browser tools |
| SSE no reconnect logic | ScrapeManager | Lost connection → lost job progress |
| Widget pipeline no cycle detection | PipelineExecutor | Circular references → infinite loops at runtime |

### Medium

| Issue | Location | Impact |
|-------|----------|--------|
| 30+ notification types could be consolidated | WheelBrowserApp | Maintainability |
| 8+ singletons in ContentView | ContentView | Hard to test, tight coupling |
| Dark mode double-application fragile | PageLifecycleHandler | Relies on navigation object identity |
| ABPParser crash | ABPParserTests | Pre-existing index out of range bug |
| FTS query sanitization incomplete | SearchDatabase | Quotes not escaped properly |
| Full-page chat is one-way latch | Tab.isChatTab | Once set, tab can never become regular again |
| Element re-matching always assigns new ID | AgentScripts | Could cause ID collision in logs |
| Streaming thought extraction lossy | AgentEngine | Fails silently if LLM format unexpected |
| ConversationHistoryBuilder no token budget | AgentManager | Multi-page contexts may exceed LLM limits |

### Low

| Issue | Location | Impact |
|-------|----------|--------|
| Hard-coded layout constants | WindowAccessor | May break on different macOS versions |
| PDF detection by extension only | SemanticIndexingHandler | Should use Content-Type header |
| Find-in-page yellow hard-coded | FindInPageController | Inaccessible on light backgrounds |
| No i18n | NavigationError, various | All strings hard-coded English |
| MIME type list not centralized | NavigationPolicyHandler | Duplicates possible |
| Overlap detection may not converge | ConstellationCanvas | 8-pass algorithm may fail at edges |
| No redirect chain detection | AgentEngine | Agent may waste steps on redirect loops |

### Test Coverage Gaps

| Gap | Recommendation |
|-----|----------------|
| AsyncRetry utility | Dedicated test file with retry/timeout/error scenarios |
| ContentView overlay system | Extract + test independently |
| BrowsingHistory disk persistence | Integration tests for I/O, corruption recovery |
| AgentEngine action dispatch | State machine tests for complex multi-step flows |
| DIndexService with mocking | Verify retry behavior, timeout handling |
| Performance benchmarks | Timing tests for ConstellationLayout, FuzzySearch |
| Error paths | Few tests for failure scenarios across subsystems |

---

## 24. File Inventory

### Source Files by Directory

```
Sources/WheelBrowser/
├── WheelBrowserApp.swift          (~371 lines)  App entry, menus, shortcuts
├── ContentView.swift              (~441 lines)  Main window layout
├── BrowserState.swift             (~349 lines)  Tab state management
├── Tab.swift                      (~228 lines)  Individual tab model
├── WindowAccessor.swift           (~190 lines)  Window chrome setup
├── NavigationError.swift          (~52 lines)   Error enum
├── FindInPageController.swift     (~172 lines)  Find-in-page JS
├── PictureInPictureController.swift (~77 lines) PiP toggle
│
├── WebView/
│   ├── BrowserWebView.swift       (~192 lines)  Custom WKWebView, context menu
│   ├── WebViewRepresentable.swift (~160 lines)  SwiftUI wrapper
│   ├── PageLifecycleHandler.swift (~178 lines)  Load lifecycle
│   ├── NavigationPolicyHandler.swift (~105 lines) Allow/download decisions
│   ├── DownloadHandler.swift      (~110 lines)  Download lifecycle
│   ├── ScriptMessageHandler.swift (~48 lines)   JS message routing
│   ├── ContextMenuBuilder.swift   (~210 lines)  Right-click menu
│   ├── ContextMenuScripts.swift   (~89 lines)   Hit-test JavaScript
│   ├── LinkHoverScripts.swift     (~53 lines)   Cmd+Click detection
│   └── SemanticIndexingHandler.swift (~99 lines) Page indexing
│
├── OmniBar/                       (~26 files, ~3,400 lines)
│   ├── OmniBar.swift              (~324 lines)  Main view
│   ├── OmniBarState.swift         (~205 lines)  Mode/panel/input state
│   ├── OmniBarEventHandlers.swift (~456 lines)  Mode/focus/keyboard handling
│   ├── OmniBarSubmissionHandlers.swift (~118 lines) Per-mode submit
│   ├── OmniBarPanels.swift        (~251 lines)  Panel layout
│   ├── OmniPanel.swift            (~122 lines)  Generic panel container
│   ├── OmniBarTextField.swift     (~157 lines)  Single-line input
│   ├── OmniBarTextEditor.swift    (~261 lines)  Multi-line input (chat)
│   ├── SuggestionsViewModel.swift (~270 lines)  Address bar suggestions
│   ├── MentionSuggestionsViewModel.swift (~296 lines) @ mention suggestions
│   ├── MentionTypes.swift         (~167 lines)  Mention enum + suggestion
│   ├── OmniBarMentions.swift      (~110 lines)  Mention chips + dropdown
│   ├── SuggestionRow.swift        (~186 lines)  Suggestion display
│   ├── ReadingListViewModel.swift (~110 lines)  Reading list search
│   └── ... (remaining sub-views, helpers)
│
├── Agent/                         (~16 files, ~4,500 lines)
│   ├── AgentEngine.swift          (~866 lines)  ReAct loop orchestrator
│   ├── AgentScripts.swift         (~552 lines)  All agent JavaScript
│   ├── AccessibilityBridge.swift  (~402 lines)  BrowserBridge implementation
│   ├── HarmonyFormatParser.swift  (~395 lines)  Structured output parser
│   ├── AgentPanelContent.swift    (~324 lines)  Agent UI panel
│   ├── AgentResponseParser.swift  (~256 lines)  THOUGHT/ACTION parser
│   ├── AgentLoopDetector.swift    (~245 lines)  Loop detection + recovery
│   ├── AgentStreamingClient.swift (~240 lines)  LLM HTTP client
│   ├── AgentPromptBuilder.swift   (~222 lines)  Prompt assembly
│   ├── PageSnapshot.swift         (~215 lines)  Page state model
│   ├── NavigationPolicy.swift     (~99 lines)   URL validation
│   ├── AgentError.swift           (~85 lines)   Error types
│   ├── ActionErrorMapper.swift    (~67 lines)   Error → LLM feedback
│   ├── AgentReasoningExtractor.swift (~57 lines) Reasoning fallback
│   ├── AgentInputValidator.swift  (~50 lines)   Input sanitization
│   └── BrowserBridge.swift        (~44 lines)   Protocol definition
│
├── Letta/                         (~6 files, ~800 lines)
│   ├── AgentManager.swift         (~597 lines)  Chat conversation manager
│   ├── LettaClient.swift          (~271 lines)  Letta API client
│   ├── LettaModels.swift          (~162 lines)  Data models
│   ├── ConversationHistoryBuilder.swift (~75 lines) Context assembly
│   ├── StreamingResponseProcessor.swift (~70 lines) SSE chunk classification
│   └── MarkdownBufferFlusher.swift (~19 lines)  Flush point detection
│
├── SemanticSearch/                (~7 files, ~1,800 lines)
│   ├── SearchDatabase.swift       (~590 lines)  SQLite reading list
│   ├── SemanticSearchManagerV2.swift (~378 lines) Search coordinator
│   ├── DIndexService.swift        (~354 lines)  DIndex actor client
│   ├── SemanticResultRow.swift    (~235 lines)  Result display
│   ├── SemanticSearchPanelContent.swift (~120 lines) Panel UI
│   ├── SemanticSearchViewModel.swift (~59 lines) Search VM
│   └── EmbeddingCategory.swift    (~37 lines)   Category enum
│
├── Constellation/                 (~8 files, ~1,800 lines)
│   ├── ConstellationView.swift    (~454 lines)  Full-screen overlay
│   ├── ConstellationCanvas.swift  (~403 lines)  Pan/zoom canvas
│   ├── ConstellationState.swift   (~228 lines)  Central state
│   ├── ConstellationLayout.swift  (~184 lines)  Force-directed layout
│   ├── ConstellationClusterer.swift (~159 lines) Domain/semantic clustering
│   ├── ConstellationPersistence.swift (~143 lines) Position persistence
│   ├── ConstellationCard.swift    (~128 lines)  Node display
│   └── ConstellationScrollZoomView.swift (~98 lines) Scroll-wheel zoom
│
├── AdBlock/                       (~8 files, ~1,400 lines)
│   ├── ABPParser.swift            (actor, ABP filter parsing)
│   ├── WebKitRuleConverter.swift  (ABP → WebKit JSON)
│   ├── ContentBlockerManager.swift (rule compilation + toggling)
│   ├── FilterList.swift           (subscription model + metadata)
│   ├── FilterListFetcher.swift    (HTTP conditional fetch)
│   ├── FilterListManager.swift    (subscription lifecycle)
│   ├── BlockingRules.swift        (~114 lines, bundled rule loading)
│   └── CookieBannerScripts.swift  (~28 lines, JS injection)
│
├── DarkMode/                      (~3 files, ~760 lines)
│   ├── DarkModeScripts.swift      (~485 lines)
│   ├── DarkModeManager.swift      (~167 lines)
│   └── DarkModeCSS.swift          (~110 lines)
│
├── History/
│   ├── BrowsingHistory.swift      (~270 lines)
│   └── FuzzySearch.swift          (~165 lines)
│
├── Scraping/                      (~3 files, ~950 lines)
│   ├── ScrapePanelContent.swift   (~385 lines)
│   ├── ScrapeManager.swift        (~358 lines)
│   └── ScrapeConfigSheet.swift    (~203 lines)
│
├── WidgetSystem/                  (~35 files, ~3,000 lines)
│   ├── PipelineExecutor.swift     (DAG execution engine)
│   ├── WidgetPipelineSpec.swift   (Spec model)
│   ├── WidgetInstance.swift       (Runtime instance)
│   ├── SkillRegistry.swift        (Skill dispatch)
│   ├── Skills/{Acquisition,Transform,Render}/  (13 skills)
│   └── ... (views, helpers, validators)
│
├── DockTabBar/
│   ├── StageManagerStrip.swift    (~174 lines)
│   └── StageManagerThumbnail.swift (~184 lines)
│
├── RightClickPanel/               (~8 files)
│   ├── TabWheelView.swift         (~170 lines)
│   ├── TabWheelState.swift        (~112 lines)
│   └── RightClickPanelContainer.swift (~203 lines)
│
├── NewTabPage/
│   └── FullPageChatView.swift     (~57 lines)
│
├── TopDrawer/
│   ├── WorkspaceManager.swift     (~282 lines)
│   ├── AgentStudioManager.swift   (~160 lines)
│   ├── AgentConfig.swift          (~142 lines)
│   └── Workspace.swift            (~105 lines)
│
├── Settings/                      (~8 files, ~380 lines)
├── Downloads/                     (DownloadManager.swift)
├── Logging/                       (Log.swift, ~451 lines)
├── LinkPreview/                   (~320 lines)
├── OverlayWindow/                 (OverlayWindowManager.swift)
├── Services/                      (SummaryGenerator.swift)
├── Extraction/                    (ContentExtractor.swift, ~104 lines)
├── Headless/                      (~3 files, ~241 lines)
├── MCP/                           (MCPServer.swift)
├── Core/                          (PersistableManager, AppContainer)
├── Shared/                        (~8 utility files)
└── Resources/                     (BlockingRules/, Scripts/, WidgetSystem/, AppIcon.icns)

Sources/WheelMCPBridge/
└── main.swift                     (~309 lines)  Stdio MCP bridge

Tests/WheelBrowserTests/           (60+ files, 350+ tests)
├── Agent/                         (7 files + fixtures)
├── WidgetSystem/                  (16+ files)
├── AdBlock/                       (2 files)
├── Constellation/                 (2 files)
├── History/                       (2 files)
├── LLM/                           (2 files)
├── Letta/                         (1 file)
├── Settings/                      (1 file)
├── Utilities/                     (5 files)
└── Workspace/                     (2 files)
```
