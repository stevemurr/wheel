import SwiftUI

/// A reusable component for displaying domain initials as a favicon placeholder
/// Used when actual favicons are not available
struct FaviconPlaceholder: View {
    let domain: String
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 6
    var style: Style = .neutral

    enum Style {
        /// Neutral gray background with secondary text
        case neutral
        /// Accent-colored background with matching text
        case accent
        /// Custom gradient based on domain hash
        case gradient
    }

    private var initial: String {
        String(domain.prefix(1)).uppercased()
    }

    private var fontSize: CGFloat {
        size * 0.43 // Proportional font size
    }

    var body: some View {
        ZStack {
            background

            Text(initial)
                .font(.system(size: fontSize, weight: style == .accent ? .semibold : .medium))
                .foregroundStyle(foregroundStyle)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .neutral:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
        case .accent:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.accentColor.opacity(0.15))
        case .gradient:
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(DomainGradient.placeholderGradient(for: domain))
        }
    }

    private var foregroundStyle: Color {
        switch style {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .gradient:
            return .white
        }
    }
}

// MARK: - Convenience Initializers

extension FaviconPlaceholder {
    /// Creates a favicon placeholder from a URL
    /// - Parameters:
    ///   - url: The URL to extract the domain from
    ///   - size: The size of the placeholder
    ///   - cornerRadius: The corner radius
    ///   - style: The visual style
    init(url: URL?, size: CGFloat = 28, cornerRadius: CGFloat = 6, style: Style = .neutral) {
        self.domain = url?.cleanDomain ?? ""
        self.size = size
        self.cornerRadius = cornerRadius
        self.style = style
    }

    /// Creates a favicon placeholder from a URL string
    /// - Parameters:
    ///   - urlString: The URL string to extract the domain from
    ///   - size: The size of the placeholder
    ///   - cornerRadius: The corner radius
    ///   - style: The visual style
    init(urlString: String, size: CGFloat = 28, cornerRadius: CGFloat = 6, style: Style = .neutral) {
        self.domain = URL(string: urlString)?.cleanDomain ?? ""
        self.size = size
        self.cornerRadius = cornerRadius
        self.style = style
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 12) {
            FaviconPlaceholder(domain: "github.com", style: .neutral)
            FaviconPlaceholder(domain: "apple.com", style: .accent)
            FaviconPlaceholder(domain: "google.com", style: .gradient)
        }

        HStack(spacing: 12) {
            FaviconPlaceholder(domain: "swift.org", size: 36, cornerRadius: 8, style: .neutral)
            FaviconPlaceholder(domain: "anthropic.com", size: 44, cornerRadius: 10, style: .accent)
        }
    }
    .padding()
}
