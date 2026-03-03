import SwiftUI

/// Shared welcome component for chat empty states.
/// `compact: true` for OmniBar panel, `compact: false` for full-screen chat.
struct WelcomeStateView: View {
    let compact: Bool
    var onSubmit: (String) -> Void

    private let capabilityCards: [(icon: String, title: String, description: String, prompt: String)] = [
        ("doc.text.magnifyingglass", "Summarize", "Condense articles & pages", "Summarize this page for me"),
        ("chevron.left.forwardslash.chevron.right", "Code", "Explain & debug code", "Explain the code on this page"),
        ("magnifyingglass", "Research", "Find & compare info", "What are the key points discussed here?"),
        ("pencil.and.outline", "Writing", "Draft & edit text", "Help me draft a response to this")
    ]

    private let quickPrompts: [String] = [
        "Summarize this page",
        "What is this about?",
        "Explain the main concepts"
    ]

    var body: some View {
        if compact {
            compactView
        } else {
            fullView
        }
    }

    // MARK: - Full Screen View

    private var fullView: some View {
        VStack(spacing: 24) {
            // Greeting
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.purple.opacity(0.6))

                Text(greeting)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Type in the bar below to start a conversation")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // 2x2 Capability cards
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(capabilityCards, id: \.title) { card in
                    CapabilityCard(
                        icon: card.icon,
                        title: card.title,
                        description: card.description
                    ) {
                        onSubmit(card.prompt)
                    }
                }
            }
            .frame(maxWidth: 500)

            // Sample prompt buttons
            HStack(spacing: 10) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button(action: { onSubmit(prompt) }) {
                        Text(prompt)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Compact View (OmniBar Panel)

    private var compactView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.purple.opacity(0.6))

            Text("How can I help?")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 6) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button(action: { onSubmit(prompt) }) {
                        HStack {
                            Image(systemName: "sparkle")
                                .font(.system(size: 9))
                                .foregroundColor(.purple.opacity(0.6))
                            Text(prompt)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary.opacity(0.7))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Helpers

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Capability Card

private struct CapabilityCard: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.purple.opacity(0.7))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.8 : 0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(isHovered ? 0.4 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
