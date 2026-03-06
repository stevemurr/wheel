# CLAUDE.md

This file provides guidance for Claude when working on the Wheel Browser codebase.

## Project Overview

Wheel is a macOS browser built with Swift and SwiftUI. It features:
- WebKit-based web rendering
- AI assistant sidebar powered by Claude
- Tab management with collapsible sidebar
- Fuzzy search for browsing history

## Build & Run

```bash
cd WheelBrowser
swift build
swift run WheelBrowser
```

## Project Structure

```
WheelBrowser/
├── Package.swift              # Swift package manifest
└── Sources/WheelBrowser/
    ├── WheelBrowserApp.swift  # App entry point and menu setup
    ├── ContentView.swift      # Main window layout
    ├── NavigationBar.swift    # URL bar and navigation controls
    ├── TabBar.swift           # Left sidebar with tabs
    ├── WebViewRepresentable.swift  # WKWebView wrapper
    ├── Chat/
    │   ├── ChatView.swift     # AI sidebar panel
    │   ├── MessageBubble.swift # Chat message display
    │   └── AgentManager.swift # AI agent logic
    ├── History/
    │   ├── BrowsingHistory.swift      # History storage
    │   ├── FuzzySearch.swift          # Fuzzy matching algorithm
    │   └── AddressBarSuggestions.swift # URL suggestions UI
    └── Settings/
        └── AppSettings.swift  # User preferences
```

## Key Design Decisions

### AI Sidebar
- Floats as a rounded panel over web content only (not title bar or nav bar)
- Hover-to-reveal: appears when hovering right edge of page
- Uses native macOS colors (`windowBackgroundColor`, `controlBackgroundColor`)
- No blur effect on web content (WKWebView doesn't support sibling view blur)

### Tab Sidebar
- Left side, supports expanded/collapsed modes
- State persisted via `@AppStorage`
- Toggle with `Cmd+Shift+S`

### Address Bar
- Fuzzy search on browsing history
- Debounced search (50ms)
- Keyboard navigation (up/down/enter/escape)
- History stored in `~/Library/Application Support/WheelBrowser/history.json`

## OmniBar Animation Invariants (CRITICAL - READ BEFORE TOUCHING OMNIBAR)

The OmniBar had a recurring flashing/flickering bug caused by overlapping SwiftUI animation contexts. The root fixes were:
1. Migrating `Tab` and `OmniBarState` to `@Observable` (per-property tracking, no blanket `objectWillChange`)
2. Removing the `.animation()` modifier from `omniBarContent` (it created an implicit animation context that overlapped with `setVisiblePanel()`'s explicit `withAnimation`, producing a flash on every focus gain)

Pill expansion is now animated explicitly via `withAnimation` on hover only. Focus-driven expansion is instant (the user is typically already hovering, and the panel animation is the dominant visual change).

### Rule 1: Prefer `@Observable` over `ObservableObject`
All new model/state classes MUST use `@Observable`. Pass them to sub-views as plain `var` (not `@ObservedObject`). Use `@State` (not `@StateObject`) when owning an `@Observable` instance. Use `@Bindable` when you need `$` binding syntax on a plain `var`. Migrate existing `ObservableObject` types when touching them. `Tab`, `OmniBarState`, `AgentManager`, `AgentEngine`, `ModuleStore`, and `WidgetStore` are already `@Observable`.

### Rule 2: No `.animation()` on omniBarContent or the parent VStack
The only implicit `.animation()` allowed in OmniBarCore is on the find-bar `Group`. `omniBarContent` must NOT have `.animation()` — it creates an implicit animation context that overlaps with `setVisiblePanel()`'s `withAnimation(panelSpring)` when both fire in the same render pass (e.g., focus gain triggers both pill expansion and panel open). Hover expansion uses explicit `withAnimation` in `.onHover`.

### Rule 3: No `withAnimation` in mode-setting methods
`setMode()`, `nextMode()`, and `previousMode()` in `OmniBarState` must NOT wrap in `withAnimation`. Mode changes trigger `onChange(of: omniState.mode)` → `handleModeChange()` → `setVisiblePanel()` which has its own `withAnimation(panelSpring)`. Adding `withAnimation` in setMode creates nested animation contexts → flash.

### Rule 4: No dismiss-then-activate in `handleModeChange`
`handleModeChange()` must NOT call `dismissVisiblePanel()` before `activateMode()`. This creates two sequential `withAnimation` blocks — the first animates to `.none`, the second animates to the new panel — causing a visible flash. Instead, `activateMode()` directly sets the new panel (atomic swap).

### Rule 5: Guard delayed dismissals against stale focus
`handleFocusLost()` uses a 200ms delay. The delayed block MUST check `isInputFocused` before dismissing, because focus may have been regained during the delay. Without this check, the delayed dismiss fires after the new panel is already open → flash.

### Rule 6: No `.contentTransition(.opacity)` on streaming content
Views that update at high frequency (chat streaming, progress indicators) must NOT use `.contentTransition(.opacity)` or per-update `.animation()` modifiers. These create overlapping opacity fades that produce a flash effect.

### Rule 7: No redundant `setVisiblePanel` calls
Handler methods (e.g., `handleFocusAISidebar`, `handleFocusSemanticSearch`) must NOT call `setVisiblePanel()` directly. `setMode()` triggers `onChange(of: mode)` → `handleModeChange()` → `activateMode()` → `setVisiblePanel()`. Calling it again creates redundant `withAnimation` transactions.

### Rule 8: Non-animated state changes BEFORE animated panel changes
In `activateMode()`, load suggestions / search results / reading list BEFORE calling `setVisiblePanel()`. View model mutations should fire before the animated panel transition to prevent non-animated body re-evals from interleaving with the transition animation.

### Rule 9: Set focus BEFORE mode in handler methods
Methods like `handleFocusAddressBar()` must set `isInputFocused = true` BEFORE `setMode()`. If mode is set first, `handleModeChange` fires and sees `isInputFocused == false`, causing it to dismiss the panel. Then the subsequent focus gain re-opens it → dismiss-then-show flash.

### Rule 10: ALWAYS wrap `isInputFocused = true` in `withAnimation(panelSpring)`
Setting `isInputFocused = true` MUST be wrapped in `withAnimation(AppAnimation.panelSpring)` — in coordinator callbacks, keyboard shortcut handlers, and any other code path. This ensures pill expansion (width, border, shadow) animates smoothly alongside the panel open from `setVisiblePanel()`. This was previously forbidden when `.animation()` was on `omniBarContent`, but now that the implicit modifier is removed, `withAnimation` on focus is the sole animation driver and does NOT overlap with anything.

### Rule 11: Extract sub-views for high-frequency data sources in OmniBar
When adding a new data source to OmniBar that updates frequently, pass it to an extracted sub-view — never read its properties directly in `OmniBar.body`. This keeps OmniBar's body re-evaluation frequency independent of the data source. See `AgentInlineStatusView`, `AgentActionButton`, `AgentPanelToggle`, and `AgentOmniPanel` as examples.

## Common Tasks

### Adding a new keyboard shortcut
1. Add notification name in `WheelBrowserApp.swift`
2. Add menu item with `keyboardShortcut()` modifier
3. Handle notification in `ContentView.swift`

### Modifying AI sidebar appearance
- `ChatView.swift` - overall panel layout and styling
- `MessageBubble.swift` - individual message appearance
- Panel uses `Color(nsColor: .windowBackgroundColor)` for native appearance

### Adding new settings
1. Add `@AppStorage` property in `Settings/AppSettings.swift`
2. Access via `AppSettings.shared` throughout the app
