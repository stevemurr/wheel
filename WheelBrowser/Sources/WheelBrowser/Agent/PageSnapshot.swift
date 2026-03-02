import Foundation

/// Represents an interactive element on the page
struct PageElement: Codable, Identifiable {
    let id: Int
    let tag: String
    let role: String?
    let text: String?
    let placeholder: String?
    let ariaLabel: String?
    let href: String?
    let isVisible: Bool
    let isEnabled: Bool
    let boundingBox: BoundingBox?

    struct BoundingBox: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    /// A human-readable description of this element for the LLM
    var description: String {
        var parts: [String] = []

        parts.append("[\(id)]")
        parts.append(tag.uppercased())

        if let role = role, !role.isEmpty {
            parts.append("role=\(role)")
        }

        if let text = text, !text.isEmpty {
            let truncated = text.count > 50 ? String(text.prefix(50)) + "..." : text
            parts.append("\"\(truncated)\"")
        }

        if let placeholder = placeholder, !placeholder.isEmpty {
            parts.append("placeholder=\"\(placeholder)\"")
        }

        if let ariaLabel = ariaLabel, !ariaLabel.isEmpty {
            parts.append("aria-label=\"\(ariaLabel)\"")
        }

        if let href = href, !href.isEmpty {
            let truncatedHref = href.count > 40 ? String(href.prefix(40)) + "..." : href
            parts.append("href=\"\(truncatedHref)\"")
        }

        if !isEnabled {
            parts.append("(disabled)")
        }

        return parts.joined(separator: " ")
    }
}

/// Represents a page heading (h1-h3) for content awareness
struct PageHeading: Codable {
    let level: Int
    let text: String
}

/// Captures what changed after an action for enriched feedback
struct ActionDelta {
    let urlChanged: Bool
    let newURL: String?
    let titleChanged: Bool
    let newTitle: String?
    let elementCountBefore: Int
    let elementCountAfter: Int
    let captchaAppeared: Bool
    let captchaDisappeared: Bool

    var significantDOMChange: Bool {
        let diff = abs(elementCountAfter - elementCountBefore)
        return diff > 5 || (elementCountBefore > 0 && Double(diff) / Double(elementCountBefore) > 0.3)
    }

    /// Human-readable description of what changed for the LLM
    var description: String {
        var parts: [String] = []

        if urlChanged, let url = newURL {
            parts.append("Page navigated to \(url).")
        }

        if titleChanged, let title = newTitle {
            parts.append("Page title changed to \"\(title)\".")
        }

        if significantDOMChange {
            parts.append("Page content changed significantly (\(elementCountBefore) → \(elementCountAfter) elements).")
        } else if elementCountAfter != elementCountBefore {
            parts.append("Minor page update (\(elementCountBefore) → \(elementCountAfter) elements).")
        }

        if captchaAppeared {
            parts.append("A captcha/challenge appeared.")
        }

        if captchaDisappeared {
            parts.append("Captcha/challenge resolved.")
        }

        return parts.isEmpty ? "No visible change." : parts.joined(separator: " ")
    }
}

/// A snapshot of the current page state
struct PageSnapshot: Codable {
    let url: String
    let title: String
    let elements: [PageElement]
    let scrollPosition: ScrollPosition
    let viewportSize: ViewportSize
    let captchaDetected: Bool
    let captchaType: String?
    let headings: [PageHeading]?
    let contentSummary: String?
    let totalElementsFound: Int?
    let elementsCapped: Bool?

    struct ScrollPosition: Codable {
        let x: Double
        let y: Double
        let maxX: Double
        let maxY: Double
    }

    struct ViewportSize: Codable {
        let width: Double
        let height: Double
    }

    /// Memberwise initializer for programmatic construction (e.g., tests)
    init(url: String, title: String, elements: [PageElement], scrollPosition: ScrollPosition, viewportSize: ViewportSize, captchaDetected: Bool = false, captchaType: String? = nil, headings: [PageHeading]? = nil, contentSummary: String? = nil, totalElementsFound: Int? = nil, elementsCapped: Bool? = nil) {
        self.url = url
        self.title = title
        self.elements = elements
        self.scrollPosition = scrollPosition
        self.viewportSize = viewportSize
        self.captchaDetected = captchaDetected
        self.captchaType = captchaType
        self.headings = headings
        self.contentSummary = contentSummary
        self.totalElementsFound = totalElementsFound
        self.elementsCapped = elementsCapped
    }

    // For backwards compatibility with existing snapshots that may not have all fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        elements = try container.decode([PageElement].self, forKey: .elements)
        scrollPosition = try container.decode(ScrollPosition.self, forKey: .scrollPosition)
        viewportSize = try container.decode(ViewportSize.self, forKey: .viewportSize)
        captchaDetected = try container.decodeIfPresent(Bool.self, forKey: .captchaDetected) ?? false
        captchaType = try container.decodeIfPresent(String.self, forKey: .captchaType)
        headings = try container.decodeIfPresent([PageHeading].self, forKey: .headings)
        contentSummary = try container.decodeIfPresent(String.self, forKey: .contentSummary)
        totalElementsFound = try container.decodeIfPresent(Int.self, forKey: .totalElementsFound)
        elementsCapped = try container.decodeIfPresent(Bool.self, forKey: .elementsCapped)
    }

    /// A text representation of the page for the LLM
    var textRepresentation: String {
        var lines: [String] = []
        lines.append("URL: \(url)")
        lines.append("Title: \(title)")
        lines.append("Viewport: \(Int(viewportSize.width))x\(Int(viewportSize.height))")
        lines.append("Scroll: \(Int(scrollPosition.y))/\(Int(scrollPosition.maxY))")

        if captchaDetected {
            lines.append("")
            lines.append("⚠️ CAPTCHA/CHALLENGE DETECTED: \(captchaType ?? "unknown type")")
            lines.append("   Call wait_for_user(\"Please solve the captcha\") to wait for the user to complete it.")
        }

        // Page headings for content awareness
        if let headings = headings, !headings.isEmpty {
            lines.append("")
            lines.append("Page Headings:")
            for heading in headings {
                let indent = String(repeating: "  ", count: heading.level)
                lines.append("\(indent)H\(heading.level): \(heading.text)")
            }
        }

        // Content summary for information-retrieval tasks
        if let summary = contentSummary, !summary.isEmpty {
            lines.append("")
            lines.append("Page Content Summary:")
            lines.append(summary)
        }

        lines.append("")
        if let capped = elementsCapped, capped, let total = totalElementsFound {
            lines.append("Interactive Elements (showing \(elements.count) of \(total). Scroll to reveal more.):")
        } else {
            lines.append("Interactive Elements:")
        }

        for element in elements where element.isVisible {
            lines.append("  \(element.description)")
        }

        return lines.joined(separator: "\n")
    }
}
