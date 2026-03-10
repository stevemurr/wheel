# Decomposition Work

## Implemented In This Pass
- Replaced the split `SearchDatabase` and `ChunkMetadataDB` storage path with a unified `PageIndexStore` actor.
- Added protocol seams for pluggability at the storage and summary boundaries:
  - `SummaryRepository`
  - `SemanticPageIndexingStore`
  - `SummaryGenerating`
  - `PageContentFetching`
- Kept legacy type names as compatibility aliases:
  - `SearchDatabase -> PageIndexStore`
  - `ChunkMetadataDB -> PageIndexStore`
- Added one-time legacy import logic so `page_index.db` can absorb rows from:
  - `semantic_search.db`
  - `semantic_search_meta.db`
- Preserved reading-list state while making semantic metadata, keyword search, summaries, and chunk mappings live in one store.
- Refactored `SummaryGenerator` so regenerate/backfill share `SummaryBatchRunner` instead of duplicating batch logic.
- Moved `snapshot(request:)` to the `BrowserBridge` protocol extension only and removed the duplicate implementation from `AccessibilityBridge`.
- Removed a few browser-state hardcoded singleton edges by making `WorkspaceStateStore` and `BrowserStateEffects` injectable.

## Verified
- `swift test --package-path WheelBrowser --filter SemanticSearch`
- `swift test --package-path WheelBrowser --filter NativeSearchIntegrationTests`
- `swift test --package-path WheelBrowser --filter BrowserStateControllerTests`

## Added Coverage
- `PageIndexStoreTests`
  - verifies migration from legacy reading-list and semantic metadata databases into the unified store
  - verifies `clearAll()` removes semantic index data while preserving saved-page records

## Remaining Work
- Build the app-level `AppDependencies` composition root and migrate production entrypoints/views away from direct `*.shared` access.
- Split `AgentEngine` into coordinator/executor/recovery/reporting components.
- Decompose `ExtensionRegistry` and `ContentBlockerManager` into protocol-backed discovery, validation, compilation, and runtime-building services.
- Replace widget prompt `if let` chains with a recognizer registry and shared alias matcher.
- Move the duplicated persistence patterns in workspace, note, conversation, agent, and widget stores behind repository protocols and shared save coordination.
