import SwiftUI

struct LLMSettingsSection: View {
    var body: some View {
        Section("AI Model") {
            HStack(spacing: 8) {
                if OnDeviceLLM.shared.isAvailable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Apple Intelligence is available")
                        .font(.system(size: 13))
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(OnDeviceLLM.shared.unavailabilityReason ?? "On-device model is not available")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Text("On-device AI — no data leaves your Mac")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
