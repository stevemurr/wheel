import SwiftUI

struct AgentAutomationOrb: View {
    var color: Color = .green
    var size: CGFloat = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let phase = phase(for: context.date)

            ZStack {
                Circle()
                    .fill(color.opacity(0.16 + (0.06 * phase)))
                    .frame(width: size * 2.8, height: size * 2.8)
                    .scaleEffect(0.72 + (0.42 * phase))
                    .opacity(0.28 + ((1 - phase) * 0.16))

                Circle()
                    .fill(color.opacity(0.22 + (0.08 * phase)))
                    .frame(width: size * 1.9, height: size * 1.9)

                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            }
            .frame(width: size * 2.8, height: size * 2.8)
        }
    }

    private func phase(for date: Date) -> Double {
        let cycle = 1.15
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return time / cycle
    }
}

struct AgentAutomationBadge: View {
    let title: String
    var subtitle: String? = nil
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            AgentAutomationOrb(size: compact ? 5 : 6)

            VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                Text(title)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty, !compact {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 7)
        .background(
            Capsule()
                .fill(Color.green.opacity(compact ? 0.18 : 0.12))
        )
        .overlay {
            Capsule()
                .strokeBorder(Color.green.opacity(0.28), lineWidth: 1)
        }
    }
}

struct AgentRoundedGlow: View {
    let cornerRadius: CGFloat
    var lineWidth: CGFloat = 2.5
    var fillOpacity: Double = 0.03

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let phase = pulse(for: context.date)

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.green.opacity(fillOpacity * (0.75 + (0.45 * phase))))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.5 + (0.18 * phase)), lineWidth: lineWidth)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.green.opacity(0.16 + (0.12 * phase)), lineWidth: lineWidth * 2.8)
                    .blur(radius: 10 + (6 * phase))
            }
            .compositingGroup()
        }
    }

    private func pulse(for date: Date) -> Double {
        let cycle = 1.4
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return (sin((time / cycle) * (.pi * 2)) + 1) / 2
    }
}

struct AgentControlledTabOverlay: View {
    let progress: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AgentAutomationBadge(
                title: "Agent is controlling this tab",
                subtitle: progress.isEmpty ? "Automation is in progress." : progress
            )
            .padding(14)
        }
        .allowsHitTesting(false)
    }
}

struct AgentControlledWindowGlow: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { context in
            let phase = pulse(for: context.date)

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.84 + (0.06 * phase)), lineWidth: 1.8)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.green.opacity(0.32 + (0.10 * phase)), lineWidth: 4)
                    .blur(radius: 5 + (2 * phase))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.green.opacity(0.14 + (0.05 * phase)), lineWidth: 9)
                    .blur(radius: 12 + (4 * phase))
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
    }

    private func pulse(for date: Date) -> Double {
        let cycle = 1.25
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return (sin((time / cycle) * (.pi * 2)) + 1) / 2
    }
}
