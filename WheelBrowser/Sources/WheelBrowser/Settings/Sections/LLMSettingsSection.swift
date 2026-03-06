import SwiftUI

struct LLMSettingsSection: View {
    @State private var availability: OnDeviceLLM.AvailabilityStatus?

    var body: some View {
        Section("AI Model") {
            HStack(spacing: 8) {
                if let availability {
                    if availability.isAvailable {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Apple Intelligence is available")
                            .font(.system(size: 13))
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(availability.reason ?? "On-device model is not available")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.secondary)
                        .opacity(0)
                    Text("Checking model availability…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Text("On-device AI — no data leaves your Mac")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .task {
            availability = await OnDeviceLLM.shared.availabilityStatus()
        }
    }
}
