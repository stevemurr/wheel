import Foundation

protocol SummaryGenerating: Sendable {
    func generateSummary(content: String) async -> String?
}

protocol PageContentFetching: Sendable {
    func fetchPageContent(url: URL) async -> String?
}

struct URLSessionPageContentFetcher: PageContentFetching {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPageContent(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)
            let _ = try response.asValidHTTPResponse()

            guard let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            return Self.extractText(fromHTML: html)
        } catch {
            return nil
        }
    }

    private static func extractText(fromHTML html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SummaryBatchRunner {
    let repository: any SummaryRepository
    let contentFetcher: any PageContentFetching
    let summaryGenerator: any SummaryGenerating

    func run(
        pages: [SavedPageRecord],
        delay: Duration,
        progressHandler: ((Int, Int) -> Void)? = nil,
        logPrefix: String
    ) async {
        for (index, page) in pages.enumerated() {
            progressHandler?(index + 1, pages.count)

            guard let content = await contentFetcher.fetchPageContent(url: page.url) else {
                Log.Services.warning("Could not fetch content for: \(page.url)")
                continue
            }

            guard let summary = await summaryGenerator.generateSummary(content: content) else {
                Log.Services.warning("Could not generate summary for: \(page.url)")
                continue
            }

            do {
                try await repository.updateSummary(url: page.url.absoluteString, summary: summary)
                Log.Services.info("\(logPrefix): \(page.url.host ?? page.url.absoluteString)")
            } catch {
                Log.Services.error("Failed to save summary: \(error)")
            }

            try? await Task.sleep(for: delay)
        }
    }
}
