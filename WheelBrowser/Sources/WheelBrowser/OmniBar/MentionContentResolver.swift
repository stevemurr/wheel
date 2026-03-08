import Foundation

/// Resolves mention references into page contexts for the AI chat.
/// Extracts actual content from each mentioned source (tabs, history, semantic search, etc.)
@MainActor
struct MentionContentResolver {
    let contentExtractor: ContentExtractor
    let browserState: BrowserState
    let currentTab: Tab
    let noteStore: NoteStore

    /// Resolve all mentions into page contexts for the given query
    func resolve(mentions: [Mention], query: String) async -> [PageContext] {
        var contexts: [PageContext] = []

        // Resolve search-context mentions (@history, @web, @readingList) first
        let hasHistory = mentions.contains { if case .history = $0 { return true } else { return false } }
        let hasWeb = mentions.contains { if case .web = $0 { return true } else { return false } }
        let hasReadingList = mentions.contains { if case .readingList = $0 { return true } else { return false } }

        if hasHistory {
            let results = BrowsingHistory.shared.search(query: query, limit: 5)
            let badge = ChatContextBadge.history(detail: results.count == 0 ? nil : "\(results.count) results")
            for entry in results {
                contexts.append(PageContext(
                    url: entry.url,
                    title: entry.title,
                    textContent: "[From History]\nURL: \(entry.url)\nTitle: \(entry.title)",
                    contextBadge: badge
                ))
            }
        }

        if hasWeb {
            let results = await SemanticSearchManagerV2.shared.search(query: query, limit: 5)
            let badge = ChatContextBadge.webSearch(resultsCount: results.count)
            for result in results {
                contexts.append(PageContext(
                    url: result.page.url,
                    title: result.page.title,
                    textContent: "[From Web]\nURL: \(result.page.url)\n\(result.page.snippet)",
                    contextBadge: badge
                ))
            }
        }

        if hasReadingList && !hasWeb {
            let results = await SemanticSearchManagerV2.shared.searchWithCategories(
                query: query, categories: [.readingList], limit: 5
            )
            let badge = ChatContextBadge.readingList(detail: results.count == 0 ? nil : "\(results.count) results")
            for result in results {
                contexts.append(PageContext(
                    url: result.page.url,
                    title: result.page.title,
                    textContent: "[From Reading List]\nURL: \(result.page.url)\n\(result.page.snippet)",
                    contextBadge: badge
                ))
            }
        }

        // Resolve per-item mentions
        for mention in mentions {
            switch mention {
            case .currentPage:
                if let context = await contentExtractor.extractContent(from: currentTab) {
                    contexts.append(context)
                }

            case .tab(let tabId, _, _):
                if let mentionedTab = browserState.tabs.first(where: { $0.id == tabId }) {
                    if let context = await contentExtractor.extractContent(from: mentionedTab) {
                        contexts.append(context)
                    }
                }

            case .overlay(_, let title, let url):
                contexts.append(PageContext(
                    url: url,
                    title: title,
                    textContent: "[Content from mini window - URL: \(url)]",
                    contextBadge: .miniWindow(title: title, url: url)
                ))

            case .note(let noteID, let title, _):
                guard let note = noteStore.note(with: noteID) else { break }
                let content = note.document.plainText(maxLength: Int.max)
                let textContent = content.isEmpty
                    ? "[From Note]\n\(title)"
                    : "[From Note]\n\(content)"
                contexts.append(PageContext(
                    url: "note://\(noteID.uuidString)",
                    title: note.displayTitle,
                    textContent: textContent,
                    contextBadge: .note(id: noteID, title: note.displayTitle)
                ))

            case .semanticResult(_, let title, let url):
                contexts.append(PageContext(
                    url: url,
                    title: title,
                    textContent: "[Content from browsing history - URL: \(url)]",
                    contextBadge: .history(title: title, url: url)
                ))

            case .history, .web, .readingList, .domain:
                break // Already handled above or not applicable
            }
        }

        return contexts
    }
}
