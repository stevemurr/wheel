import Foundation

/// Decoded result of the JS hit-test performed on right-click.
struct ContextMenuHitTest: Codable {
    var linkURL: String
    var linkText: String
    var imageSrc: String
    var imageAlt: String
    var mediaSrc: String
    var mediaTagName: String
    var mediaCurrentTime: Double?
    var selectedText: String
    var isEditable: Bool
    var pageCanonicalURL: String
    var pageURL: String
    var pageTitle: String

    static let empty = ContextMenuHitTest(
        linkURL: "", linkText: "",
        imageSrc: "", imageAlt: "",
        mediaSrc: "", mediaTagName: "", mediaCurrentTime: nil,
        selectedText: "", isEditable: false,
        pageCanonicalURL: "",
        pageURL: "", pageTitle: ""
    )
}

/// Pure-logic menu construction from a `ContextMenuHitTest`.
///
/// Returns structured `ContextMenuSection` data instead of `NSMenu` items.
/// Navigation items (Back/Forward/Reload) are handled by the card's chip bar,
/// so they are not included in the returned sections.
enum ContextMenuBuilder {

    /// Build context menu sections for the given hit-test result.
    ///
    /// Navigation actions are excluded — the card renders those as chips.
    static func buildSections(
        for hitTest: ContextMenuHitTest,
        canGoBack: Bool,
        canGoForward: Bool
    ) -> [ContextMenuSection] {
        var sections: [ContextMenuSection] = []

        // --- Link items ---
        if !hitTest.linkURL.isEmpty {
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(
                    title: "Open Link in New Tab",
                    systemImage: "plus.rectangle.on.rectangle",
                    action: .openLinkInNewTab(url: hitTest.linkURL)
                ),
                ContextMenuItem(
                    title: "Copy Link Address",
                    systemImage: "doc.on.doc",
                    action: .copyLinkAddress(url: hitTest.linkURL)
                ),
            ]))
        }

        // --- Image items ---
        if !hitTest.imageSrc.isEmpty {
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(
                    title: "Open Image in New Tab",
                    systemImage: "photo",
                    action: .openImageInNewTab(url: hitTest.imageSrc)
                ),
                ContextMenuItem(
                    title: "Save Image As\u{2026}",
                    systemImage: "square.and.arrow.down",
                    action: .saveImageAs(url: hitTest.imageSrc)
                ),
                ContextMenuItem(
                    title: "Copy Image",
                    systemImage: "doc.on.doc",
                    action: .copyImage(url: hitTest.imageSrc)
                ),
                ContextMenuItem(
                    title: "Copy Image Address",
                    systemImage: "doc.on.doc",
                    action: .copyImageAddress(url: hitTest.imageSrc)
                ),
            ]))
        }

        // --- Media items ---
        if !hitTest.mediaSrc.isEmpty {
            let label = hitTest.mediaTagName == "audio" ? "Audio" : "Video"
            let resolvedMediaURL = resolvedMediaURL(for: hitTest)
            var mediaItems: [ContextMenuItem] = []

            if let resolvedMediaURL {
                mediaItems.append(
                    ContextMenuItem(
                        title: "Open \(label) in New Tab",
                        systemImage: "plus.rectangle.on.rectangle",
                        action: .openMediaInNewTab(url: resolvedMediaURL, label: label)
                    )
                )
                mediaItems.append(
                    ContextMenuItem(
                        title: "Copy \(label) Address",
                        systemImage: "doc.on.doc",
                        action: .copyMediaAddress(url: resolvedMediaURL)
                    )
                )
            }

            if label == "Video",
               let timestampedURL = timestampedMediaURL(for: hitTest) {
                mediaItems.append(
                    ContextMenuItem(
                        title: "Copy Video at Current Timestamp",
                        systemImage: "clock",
                        action: .copyMediaAtTimestamp(url: timestampedURL)
                    )
                )
            }

            if !mediaItems.isEmpty {
                sections.append(ContextMenuSection(items: mediaItems))
            }
        }

        // --- Editable items ---
        if hitTest.isEditable {
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(title: "Cut", systemImage: "scissors", action: .cut),
                ContextMenuItem(title: "Copy", systemImage: "doc.on.doc", action: .copy),
                ContextMenuItem(title: "Paste", systemImage: "doc.on.clipboard", action: .paste),
                ContextMenuItem(title: "Select All", systemImage: "selection.pin.in.out", action: .selectAll),
            ]))
        }

        // --- Selection items (non-editable) ---
        if !hitTest.selectedText.isEmpty && !hitTest.isEditable {
            let preview = hitTest.selectedText.count > 20
                ? String(hitTest.selectedText.prefix(20)) + "\u{2026}"
                : hitTest.selectedText
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(
                    title: "Copy",
                    systemImage: "doc.on.doc",
                    action: .copySelection(text: hitTest.selectedText)
                ),
                ContextMenuItem(
                    title: "Search Web for \"\(preview)\"",
                    systemImage: "magnifyingglass",
                    action: .searchWebFor(text: hitTest.selectedText)
                ),
            ]))
        }

        // --- Note capture ---
        if !hitTest.pageURL.isEmpty {
            sections.append(ContextMenuSection(items: [
                ContextMenuItem(
                    title: "New Note",
                    systemImage: "square.and.pencil",
                    action: .newNote
                ),
            ]))
        }

        return sections
    }

    private static func resolvedMediaURL(for hitTest: ContextMenuHitTest) -> String? {
        let candidates = [
            hitTest.mediaSrc,
            hitTest.linkURL,
            hitTest.pageCanonicalURL,
            hitTest.pageURL,
        ]

        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { candidate in
                !candidate.isEmpty && !isEphemeralMediaURL(candidate)
            }
    }

    private static func timestampedMediaURL(for hitTest: ContextMenuHitTest) -> String? {
        guard hitTest.mediaTagName == "video",
              let baseURLString = resolvedMediaURL(for: hitTest),
              let seconds = sanitizedTimestamp(from: hitTest.mediaCurrentTime) else {
            return nil
        }

        guard let baseURL = URL(string: baseURLString) else {
            return nil
        }

        if isYouTubeURL(baseURL) {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                return nil
            }

            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name == "t" || $0.name == "time_continue" }
            queryItems.append(URLQueryItem(name: "t", value: "\(seconds)s"))
            components.queryItems = queryItems
            return components.url?.absoluteString
        }

        guard !isEphemeralMediaURL(hitTest.mediaSrc),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.fragment = "t=\(seconds)"
        return components.url?.absoluteString
    }

    private static func sanitizedTimestamp(from value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return max(Int(value.rounded(.down)), 0)
    }

    private static func isEphemeralMediaURL(_ urlString: String) -> Bool {
        let normalized = urlString.lowercased()
        return normalized.hasPrefix("blob:") ||
            normalized.hasPrefix("data:") ||
            normalized.hasPrefix("javascript:")
    }

    private static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtube.com" ||
            host.hasSuffix(".youtube.com") ||
            host == "youtu.be" ||
            host.hasSuffix(".youtu.be")
    }
}
