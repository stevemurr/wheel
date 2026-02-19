import Foundation
import SwiftSoup

/// Fetches and extracts content from various data sources
actor AIWidgetContentFetcher {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) WheelBrowser/1.0"
        ]
        self.session = URLSession(configuration: config)
    }

    /// Fetch and extract content based on the widget configuration
    func fetch(config: AIWidgetConfig) async throws -> ExtractedContent {
        guard let url = URL(string: config.source.url) else {
            throw FetchError.invalidURL(config.source.url)
        }

        var request = URLRequest(url: url)
        for (key, value) in config.source.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FetchError.httpError(httpResponse.statusCode)
        }

        let content: ExtractedContent

        switch config.source.type {
        case .urlFetch:
            content = try extractFromHTML(data: data, config: config)
        case .jsonApi:
            content = try extractFromJSON(data: data, config: config)
        case .rssFeed:
            content = try extractFromRSS(data: data, config: config)
        }

        return content
    }

    // MARK: - HTML Extraction

    private func extractFromHTML(data: Data, config: AIWidgetConfig) throws -> ExtractedContent {
        guard let html = String(data: data, encoding: .utf8) else {
            throw FetchError.invalidEncoding
        }

        let document = try SwiftSoup.parse(html)
        var items: [ExtractedItem] = []

        // If we have an item selector, extract multiple items
        if let itemSelector = config.extraction.itemSelector {
            let elements = try document.select(itemSelector)

            for element in elements.prefix(config.display.itemLimit) {
                var fields: [String: String] = [:]
                var link: URL?

                for (fieldName, selector) in config.extraction.selectors {
                    if let fieldElement = try? element.select(selector).first() {
                        if fieldName == "link" || selector.contains("[href]") {
                            if let href = try? fieldElement.attr("href") {
                                link = URL(string: href)
                                fields[fieldName] = href
                            }
                        } else if selector.contains("[src]") {
                            if let src = try? fieldElement.attr("src") {
                                fields[fieldName] = src
                            }
                        } else {
                            fields[fieldName] = try fieldElement.text()
                        }
                    }
                }

                if !fields.isEmpty {
                    items.append(ExtractedItem(fields: fields, link: link))
                }
            }
        } else {
            // Single item extraction
            var fields: [String: String] = [:]
            var link: URL?

            for (fieldName, selector) in config.extraction.selectors {
                if let element = try? document.select(selector).first() {
                    if fieldName == "link" {
                        if let href = try? element.attr("href") {
                            link = URL(string: href)
                            fields[fieldName] = href
                        }
                    } else {
                        fields[fieldName] = try element.text()
                    }
                }
            }

            if !fields.isEmpty {
                items.append(ExtractedItem(fields: fields, link: link))
            }
        }

        return ExtractedContent(items: items, fetchedAt: Date())
    }

    // MARK: - JSON Extraction

    private func extractFromJSON(data: Data, config: AIWidgetConfig) throws -> ExtractedContent {
        guard let jsonPaths = config.extraction.jsonPaths else {
            throw FetchError.missingJSONPaths
        }

        let json = try JSONSerialization.jsonObject(with: data)

        // Find the array of items using the itemSelector as a path
        let itemsArray: [Any]
        if let itemPath = config.extraction.itemSelector {
            itemsArray = extractJSONPath(from: json, path: itemPath) as? [Any] ?? []
        } else if let array = json as? [Any] {
            itemsArray = array
        } else {
            itemsArray = [json]
        }

        var items: [ExtractedItem] = []

        for item in itemsArray.prefix(config.display.itemLimit) {
            var fields: [String: String] = [:]
            var link: URL?

            for (fieldName, path) in jsonPaths {
                if let value = extractJSONPath(from: item, path: path) {
                    let stringValue = stringifyJSON(value)
                    fields[fieldName] = stringValue

                    if fieldName == "link" || fieldName == "url" {
                        link = URL(string: stringValue)
                    }
                }
            }

            if !fields.isEmpty {
                items.append(ExtractedItem(fields: fields, link: link))
            }
        }

        return ExtractedContent(items: items, fetchedAt: Date())
    }

    /// Simple JSON path extraction (supports dot notation and array indices)
    private func extractJSONPath(from json: Any, path: String) -> Any? {
        var current: Any? = json
        let components = path.split(separator: ".").map(String.init)

        for component in components {
            guard let currentDict = current else { return nil }

            // Check for array index: items[0]
            if let bracketStart = component.firstIndex(of: "["),
               let bracketEnd = component.firstIndex(of: "]") {
                let key = String(component[..<bracketStart])
                let indexStr = String(component[component.index(after: bracketStart)..<bracketEnd])

                if key.isEmpty {
                    // Direct array access: [0]
                    if let array = currentDict as? [Any],
                       let index = Int(indexStr),
                       index < array.count {
                        current = array[index]
                    } else {
                        return nil
                    }
                } else {
                    // Named array access: items[0]
                    if let dict = currentDict as? [String: Any],
                       let array = dict[key] as? [Any],
                       let index = Int(indexStr),
                       index < array.count {
                        current = array[index]
                    } else {
                        return nil
                    }
                }
            } else {
                // Simple key access
                if let dict = currentDict as? [String: Any] {
                    current = dict[component]
                } else {
                    return nil
                }
            }
        }

        return current
    }

    private func stringifyJSON(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            if let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return String(describing: value)
        }
    }

    // MARK: - RSS Extraction

    private func extractFromRSS(data: Data, config: AIWidgetConfig) throws -> ExtractedContent {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw FetchError.invalidEncoding
        }

        let document = try SwiftSoup.parse(xmlString, "", Parser.xmlParser())
        var items: [ExtractedItem] = []

        // Try RSS 2.0 format first
        var itemElements = try document.select("item")

        // If no items found, try Atom format
        if itemElements.isEmpty() {
            itemElements = try document.select("entry")
        }

        for element in itemElements.prefix(config.display.itemLimit) {
            var fields: [String: String] = [:]
            var link: URL?

            // RSS 2.0 fields
            if let title = try? element.select("title").first()?.text() {
                fields["title"] = title
            }

            if let description = try? element.select("description").first()?.text() {
                fields["description"] = cleanHTMLFromText(description)
            } else if let content = try? element.select("content").first()?.text() {
                fields["description"] = cleanHTMLFromText(content)
            } else if let summary = try? element.select("summary").first()?.text() {
                fields["description"] = cleanHTMLFromText(summary)
            }

            // Try multiple link formats
            if let linkElement = try? element.select("link").first() {
                let href = try? linkElement.attr("href")
                let text = try? linkElement.text()
                let linkStr = (href?.isEmpty == false ? href : text) ?? ""
                if !linkStr.isEmpty {
                    fields["link"] = linkStr
                    link = URL(string: linkStr)
                }
            }

            if let pubDate = try? element.select("pubDate").first()?.text() {
                fields["date"] = pubDate
            } else if let published = try? element.select("published").first()?.text() {
                fields["date"] = published
            } else if let updated = try? element.select("updated").first()?.text() {
                fields["date"] = updated
            }

            if let author = try? element.select("author").first()?.text() {
                fields["author"] = author
            } else if let creator = try? element.select("dc\\:creator").first()?.text() {
                fields["author"] = creator
            }

            if !fields.isEmpty {
                items.append(ExtractedItem(fields: fields, link: link))
            }
        }

        return ExtractedContent(items: items, fetchedAt: Date())
    }

    private func cleanHTMLFromText(_ text: String) -> String {
        // Simple HTML tag removal for RSS descriptions
        guard let doc = try? SwiftSoup.parse(text) else {
            return text
        }
        return (try? doc.text()) ?? text
    }

    // MARK: - Errors

    enum FetchError: LocalizedError {
        case invalidURL(String)
        case invalidResponse
        case httpError(Int)
        case invalidEncoding
        case missingJSONPaths
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            case .invalidResponse:
                return "Invalid response from server"
            case .httpError(let code):
                return "HTTP error: \(code)"
            case .invalidEncoding:
                return "Could not decode response"
            case .missingJSONPaths:
                return "JSON paths not configured"
            case .extractionFailed(let reason):
                return "Extraction failed: \(reason)"
            }
        }
    }
}
