# Semantic Search - Next Steps

## Current Status: COMPLETE (ready to test)

The semantic search system is fully implemented with:
- sqlite-vec for vector storage
- Hybrid search (vector + FTS with RRF fusion)
- Chunking with overlap (~500 tokens/chunk)
- Configurable embedding providers (OpenAI, Voyage, Local, Custom)
- Settings UI with stats, clear button, dimension change warnings
- Auto-reinitialize when settings change
- Index cleared automatically when dimensions change

## To Test

1. Run the app: `cd WheelBrowser && swift run`
2. Go to Settings → Semantic Search
3. Select "OpenAI" as provider
4. Enter your OpenAI API key and click Save
5. Browse some pages
6. Check settings - should show pages indexed count
7. Use semantic search in OmniBar

## Optional Enhancements

### 1. LLM-Generated Summaries (Low Priority)
Currently uses first chunk as summary. Could call Claude/GPT to generate better summaries.

Location: `Sources/WheelBrowser/SemanticSearch/IndexingPipeline.swift` line 74-78
```swift
// Stage 5: Generate summary embedding (use first chunk as summary for now)
// In production, you'd call an LLM to generate a proper summary
let summaryText = chunks.first ?? page.title ?? ""
```

### 2. Remove Old SemanticSearchManager (Cleanup)
The old USearch-based manager still exists but is no longer used.

File to delete: `Sources/WheelBrowser/SemanticSearch/SemanticSearchManager.swift`

### 3. Migration from Old Index (If Needed)
If users have existing data in the old USearch index, could migrate it.
Old files location:
- `~/Library/Application Support/WheelBrowser/semantic.usearch`
- `~/Library/Application Support/WheelBrowser/semantic_pages.json`

## Architecture Reference

```
Page Load → ContentExtractor → IndexingPipeline
                                    ↓
                              Chunking (~500 tokens, 50 overlap)
                                    ↓
                              EmbeddingService (API or local)
                                    ↓
                              SearchDatabase (sqlite-vec)
                              ├── pages table (metadata)
                              ├── chunks table
                              ├── pages_fts (FTS5)
                              ├── chunks_fts (FTS5)
                              ├── pages_title_vec (vec0)
                              ├── pages_summary_vec (vec0)
                              └── chunks_vec (vec0)

Query → SearchEngine
            ↓
    ├── Embed query
    ├── Vector search (summary → title → chunks)
    ├── FTS search (pages + chunks)
    ├── RRF fusion
    ├── Time decay + frequency boost
    └── Top K results
```

## Key Files

- `Packages/SqliteVec/` - sqlite-vec Swift wrapper
- `Sources/WheelBrowser/SemanticSearch/`
  - `EmbeddingService.swift` - API + local embedding
  - `SearchDatabase.swift` - SQLite + sqlite-vec storage
  - `SearchEngine.swift` - Hybrid search logic
  - `IndexingPipeline.swift` - Background indexing
  - `SemanticSearchManagerV2.swift` - Main coordinator
- `Sources/WheelBrowser/Settings/`
  - `AppSettings.swift` - Embedding settings
  - `SettingsView.swift` - Settings UI

## Database Location

`~/Library/Application Support/WheelBrowser/semantic_search.db`
