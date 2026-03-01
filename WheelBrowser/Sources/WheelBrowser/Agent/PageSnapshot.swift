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

/// A snapshot of the current page state
struct PageSnapshot: Codable {
    let url: String
    let title: String
    let elements: [PageElement]
    let scrollPosition: ScrollPosition
    let viewportSize: ViewportSize
    let captchaDetected: Bool
    let captchaType: String?

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

    // For backwards compatibility with existing snapshots that don't have captcha fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        elements = try container.decode([PageElement].self, forKey: .elements)
        scrollPosition = try container.decode(ScrollPosition.self, forKey: .scrollPosition)
        viewportSize = try container.decode(ViewportSize.self, forKey: .viewportSize)
        captchaDetected = try container.decodeIfPresent(Bool.self, forKey: .captchaDetected) ?? false
        captchaType = try container.decodeIfPresent(String.self, forKey: .captchaType)
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

        lines.append("")
        lines.append("Interactive Elements:")

        for element in elements where element.isVisible {
            lines.append("  \(element.description)")
        }

        return lines.joined(separator: "\n")
    }
}
