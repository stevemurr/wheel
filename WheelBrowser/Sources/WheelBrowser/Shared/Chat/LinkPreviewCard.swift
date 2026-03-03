import SwiftUI
import LinkPresentation

/// Card component that fetches and displays URL metadata (title, description, favicon).
struct LinkPreviewCard: View {
    let url: URL

    @State private var title: String?
    @State private var siteName: String?
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        if failed {
            // Fallback: simple link
            Link(destination: url) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    Text(url.host ?? url.absoluteString)
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                }
            }
        } else {
            HStack(spacing: 10) {
                // Favicon placeholder
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor.opacity(0.6))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    if isLoading {
                        Text("Loading preview...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        if let title = title {
                            Text(title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }

                        Text(url.host ?? url.absoluteString)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.2), lineWidth: 1)
            )
            .onTapGesture {
                NSWorkspace.shared.open(url)
            }
            .task {
                await fetchMetadata()
            }
        }
    }

    private func fetchMetadata() async {
        let provider = LPMetadataProvider()
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            self.title = metadata.title
            self.siteName = metadata.value(forKey: "siteName") as? String
            self.isLoading = false
        } catch {
            self.failed = true
            self.isLoading = false
        }
    }
}

/// Detects standalone URLs in text content
enum URLDetector {
    /// Find standalone URLs in text (not inside markdown links)
    static func findStandaloneURLs(in text: String) -> [URL] {
        // Match URLs that are on their own line or standalone
        let pattern = #"(?:^|\s)(https?://[^\s\]\)]+)(?:\s|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { match -> URL? in
            let urlRange = match.range(at: 1)
            guard urlRange.length > 0 else { return nil }
            let urlString = nsText.substring(with: urlRange)
            return URL(string: urlString)
        }
    }
}
