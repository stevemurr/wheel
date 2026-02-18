import SwiftUI

struct DockTabItem: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let isHovered: Bool
    let tabCount: Int
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var showClose = false
    @State private var agentPulseScale: CGFloat = 1.0

    private let size: CGFloat = 44
    private let cornerRadius: CGFloat = 10

    private var tabBackground: Color {
        if isActive {
            return Color(nsColor: .controlAccentColor)
        } else {
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        }
    }

    private var textColor: Color {
        if isActive {
            return .white
        } else {
            return Color(nsColor: .secondaryLabelColor)
        }
    }

    var body: some View {
        ZStack {
            // Rounded square background
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tabBackground)
                .frame(width: size, height: size)

            // Agent activity indicator (pulsing border)
            if tab.hasActiveAgent {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.green, lineWidth: 2)
                    .frame(width: size, height: size)
                    .scaleEffect(agentPulseScale)
                    .opacity(2 - agentPulseScale)
            }

            // Favicon or domain initial
            faviconContent

            // Agent spinner indicator
            if tab.hasActiveAgent {
                ProgressView()
                    .scaleEffect(0.4)
                    .offset(x: -size / 2 + 10, y: -size / 2 + 10)
            }

            // Close button on hover
            if showClose && tabCount > 1 && !tab.hasActiveAgent {
                closeButton
            }
        }
        .scaleEffect(isHovered ? 1.15 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onTapGesture(perform: onSelect)
        .onHover { showClose = $0 }
        .help(tab.hasActiveAgent ? "\(tab.title) (Agent running)" : tab.title)
        .onAppear {
            startAgentPulseAnimation()
        }
        .onChange(of: tab.hasActiveAgent) { _, hasAgent in
            if hasAgent {
                startAgentPulseAnimation()
            }
        }
    }

    private func startAgentPulseAnimation() {
        guard tab.hasActiveAgent else { return }
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            agentPulseScale = 1.15
        }
    }

    private var faviconContent: some View {
        Group {
            if let url = tab.url, let host = url.host {
                Text(String(host.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(textColor)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundColor(textColor)
            }
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(textColor.opacity(0.8))
        }
        .buttonStyle(.plain)
        .offset(x: size / 2 - 8, y: -size / 2 + 8)
    }
}
