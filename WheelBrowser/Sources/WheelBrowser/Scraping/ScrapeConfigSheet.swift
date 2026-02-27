import SwiftUI

// MARK: - URL Identifiable Extension

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Configuration sheet for starting a scrape job
struct ScrapeConfigSheet: View {
    let url: URL
    let onStart: (ScrapeConfig) -> Void
    let onCancel: () -> Void

    @State private var depth: UInt8 = 1
    @State private var stayOnDomain: Bool = true
    @State private var maxPages: Int = 100

    /// Display string for the URL host
    private var displayHost: String {
        url.host ?? url.absoluteString
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            // Options
            VStack(alignment: .leading, spacing: 16) {
                depthSelector
                domainToggle
                maxPagesSlider
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Footer
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.cyan)

            Text("Scrape Page")
                .font(.system(size: 17, weight: .semibold))

            Text(displayHost)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Depth Selector

    private var depthSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Link Depth")
                .font(.system(size: 13, weight: .medium))

            HStack(spacing: 8) {
                ForEach([0, 1, 2, 3] as [UInt8], id: \.self) { level in
                    depthButton(level: level)
                }
            }
        }
    }

    private func depthButton(level: UInt8) -> some View {
        Button(action: { depth = level }) {
            Text(depthLabel(for: level))
                .font(.system(size: 12, weight: depth == level ? .semibold : .regular))
                .foregroundColor(depth == level ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(depth == level ? Color.cyan : Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
    }

    private func depthLabel(for level: UInt8) -> String {
        switch level {
        case 0: return "This page"
        case 1: return "1 level"
        default: return "\(level) levels"
        }
    }

    // MARK: - Domain Toggle

    private var domainToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $stayOnDomain) {
                Text("Stay on domain")
                    .font(.system(size: 13, weight: .medium))
            }
            .toggleStyle(.checkbox)

            Text("Only follow links to \(displayHost)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 20)
        }
    }

    // MARK: - Max Pages Slider

    private var maxPagesSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Maximum pages")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(maxPages)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(maxPages) },
                    set: { maxPages = Int($0) }
                ),
                in: 10...500,
                step: 10
            )
            .tint(.cyan)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.escape)

            Spacer()

            Button(action: {
                let config = ScrapeConfig(
                    url: url,
                    depth: depth,
                    stayOnDomain: stayOnDomain,
                    maxPages: maxPages
                )
                onStart(config)
            }) {
                Text("Start Scraping")
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .keyboardShortcut(.return)
        }
    }
}

/// Configuration for a scrape job
struct ScrapeConfig {
    let url: URL
    let depth: UInt8
    let stayOnDomain: Bool
    let maxPages: Int
}

// MARK: - Preview

#if DEBUG
struct ScrapeConfigSheet_Previews: PreviewProvider {
    static var previews: some View {
        ScrapeConfigSheet(
            url: URL(string: "https://example.com/docs")!,
            onStart: { _ in },
            onCancel: { }
        )
    }
}
#endif
