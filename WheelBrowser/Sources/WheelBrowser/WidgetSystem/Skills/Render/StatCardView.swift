import SwiftUI

/// Renders a `RenderInput.statCard` as a single KPI card.
struct StatCardView: View {
    let label: String
    let value: String
    let format: ValueFormat
    let delta: Delta?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if let delta {
                HStack(spacing: 4) {
                    Image(systemName: delta.value >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))

                    Text(formatDelta(delta.value))
                        .font(.system(size: 11, weight: .medium))

                    if let deltaLabel = delta.label {
                        Text(deltaLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(delta.value >= 0 ? .green : .red)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(delta.value >= 0 ? "Up" : "Down") \(formatDelta(delta.value))\(delta.label.map { " \($0)" } ?? "")")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDelta(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "%+.1fK", value / 1000)
        }
        if abs(value) < 1 {
            return String(format: "%+.2f", value)
        }
        return String(format: "%+.1f", value)
    }
}
