import SwiftUI

// MARK: - Semantic Result Row

struct SemanticResultRow: View {
    let result: SemanticSearchResult
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false
    @State private var isExpanded = false

    /// Cached domain extracted from URL (computed once at init)
    private let cachedDomain: String
    /// Cached display URL (computed once at init)
    private let cachedDisplayURL: String
    /// Cached domain color (computed once at init)
    private let cachedDomainColor: Color
    /// Query terms that matched (for highlighting)
    private let matchedTerms: [String]

    init(result: SemanticSearchResult, isSelected: Bool, searchQuery: String = "", onSelect: @escaping () -> Void) {
        self.result = result
        self.isSelected = isSelected
        self.onSelect = onSelect

        // Pre-compute expensive string operations
        self.cachedDomain = result.page.url.urlCleanDomain

        // Pre-compute display URL
        self.cachedDisplayURL = URLFormatter.shared.displayURL(result.page.url, maxLength: 50)

        // Pre-compute domain color using shared utility
        self.cachedDomainColor = DomainColor.color(for: result.page.url.urlCleanDomain)

        // Split search query into words for highlighting
        self.matchedTerms = searchQuery
            .split(separator: " ")
            .map { String($0) }
            .filter { $0.count >= 2 }
    }

    private var scorePercentage: Int {
        Int(result.score * 100)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Favicon
            faviconView
                .frame(width: 28, height: 28)

            // Title, citation, and URL
            VStack(alignment: .leading, spacing: 3) {
                highlightTerms(in: result.page.title.isEmpty ? cachedDomain : result.page.title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                // Citation view with section breadcrumbs and quote-styled content
                if let citation = result.page.citation {
                    citationView(citation)
                } else if !result.page.snippet.isEmpty {
                    highlightTerms(in: result.page.snippet)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }

                // Expand/collapse for additional citations
                if !result.page.additionalCitations.isEmpty {
                    Button(action: {
                        withAnimation(AppAnimation.standard) {
                            isExpanded.toggle()
                        }
                    }) {
                        Text("\(isExpanded ? "▾" : "▸") \(result.page.additionalCitations.count) more citation\(result.page.additionalCitations.count == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        ForEach(Array(result.page.additionalCitations.enumerated()), id: \.offset) { _, citation in
                            citationView(citation)
                        }
                    }
                }

                // Matched-by badges
                if !result.page.documentMatchedBy.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(result.page.documentMatchedBy.sorted()), id: \.self) { method in
                            matchedByBadge(method)
                        }
                    }
                }

                Text(cachedDisplayURL)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            // Similarity score
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(scorePercentage)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(scoreColor)

                Text("match")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(scoreColor.opacity(0.1))
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.orange.opacity(0.2)
        } else if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.5)
        }
        return Color.clear
    }

    private var scoreColor: Color {
        if result.score > 0.8 {
            return .green
        } else if result.score > 0.5 {
            return .orange
        } else {
            return .secondary
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if !cachedDomain.isEmpty {
            let initial = String(cachedDomain.prefix(1)).uppercased()
            Text(initial)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(cachedDomainColor)
                )
        } else {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
    }

    @ViewBuilder
    private func citationView(_ citation: CitationInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Section breadcrumbs (chevron-separated hierarchy)
            if !citation.sectionHierarchy.isEmpty {
                Text(citation.sectionHierarchy.joined(separator: " › "))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Quote-styled content with orange left bar
            HStack(alignment: .top, spacing: 6) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 2)

                let snippetText = citation.snippet ?? (result.page.snippet.isEmpty ? String(citation.content.prefix(200)) : result.page.snippet)
                highlightTerms(in: snippetText)
                    .font(.system(size: 11))
                    .italic()
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func matchedByBadge(_ method: String) -> some View {
        let (label, color): (String, Color) = {
            switch method.lowercased() {
            case "dense":
                return ("Semantic", .purple)
            case "bm25":
                return ("Keyword", .blue)
            default:
                return (method.capitalized, .gray)
            }
        }()

        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    /// Highlight occurrences of matched query terms in the given string
    private func highlightTerms(in string: String) -> Text {
        HighlightedTextBuilder.fromTerms(string, terms: matchedTerms)
    }
}
