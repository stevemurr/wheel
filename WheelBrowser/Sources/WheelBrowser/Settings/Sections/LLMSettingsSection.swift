import SwiftUI

struct LLMSettingsSection: View {
    @AppStorage(AppSettings.aiProviderIDKey) private var providerID = WheelModelProviderID.apple.rawValue
    @AppStorage(AppSettings.aiModelIDKey) private var modelID = WheelModelProviderID.apple.defaultModelID
    @AppStorage(AppSettings.aiBaseURLKey) private var baseURL = ""
    @AppStorage(AppSettings.aiContextWindowOverrideKey) private var contextWindowOverride = 0
    @AppStorage(AppSettings.aiAppleGuardrailsKey) private var appleGuardrails = WheelAppleGuardrailsOption.default.rawValue

    @State private var availability: WheelModelAvailability?
    @State private var apiKey = ""

    private let secretStore: any WheelModelSecretStoring = KeychainWheelModelSecretStore.shared

    private var selectedProvider: WheelModelProviderID {
        WheelModelProviderID(rawValue: providerID) ?? .apple
    }

    private var profileSummary: String {
        WheelModelConfigurationProvider.shared.currentProfile().displayName
    }

    private var contextWindowOverrideText: Binding<String> {
        Binding(
            get: { contextWindowOverride > 0 ? String(contextWindowOverride) : "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                contextWindowOverride = Int(trimmed) ?? 0
            }
        )
    }

    var body: some View {
        Section("AI Model") {
            Picker("Provider", selection: $providerID) {
                ForEach(WheelModelProviderID.allCases, id: \.rawValue) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }
            .pickerStyle(.menu)

            TextField("Model ID", text: $modelID)

            if selectedProvider.requiresBaseURL {
                TextField("Base URL", text: $baseURL)
            }

            if selectedProvider == .apple {
                Picker("Guardrails", selection: $appleGuardrails) {
                    ForEach(WheelAppleGuardrailsOption.allCases, id: \.rawValue) { guardrails in
                        Text(guardrails.displayName).tag(guardrails.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text("Context Window Override")
                Spacer()
                TextField("Default", text: contextWindowOverrideText)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
            }

            if selectedProvider.requiresAPIKey || selectedProvider.supportsOptionalAPIKey {
                SecureField(selectedProvider.apiKeyLabel, text: $apiKey)

                HStack {
                    Button("Save API Key") {
                        saveAPIKey()
                    }
                    .buttonStyle(.bordered)

                    Button("Clear Saved Key") {
                        apiKey = ""
                        saveAPIKey()
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(profileSummary)
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 8) {
                    if let availability {
                        Image(systemName: availability.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(availability.isAvailable ? .green : .orange)
                        Text(
                            availability.isAvailable
                                ? "\(availability.displayName) is available"
                                : (availability.reason ?? "\(availability.displayName) is unavailable")
                        )
                        .font(.system(size: 13))
                        .foregroundColor(availability.isAvailable ? .primary : .secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking model availability…")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                Text(modelDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .task {
            loadAPIKey()
            await refreshAvailability()
        }
        .onChange(of: providerID) { _, newValue in
            let provider = WheelModelProviderID(rawValue: newValue) ?? .apple
            modelID = provider.defaultModelID
            loadAPIKey()
            Task { await refreshAvailability() }
        }
        .onChange(of: modelID) { _, _ in
            Task { await refreshAvailability() }
        }
        .onChange(of: baseURL) { _, _ in
            Task { await refreshAvailability() }
        }
        .onChange(of: appleGuardrails) { _, _ in
            Task { await refreshAvailability() }
        }
        .onChange(of: contextWindowOverride) { _, _ in
            Task { await refreshAvailability() }
        }
    }

    private var modelDetail: String {
        switch selectedProvider {
        case .apple:
            return availability?.reason ?? "On-device inference stays on this Mac."
        case .openAI, .vllm:
            return availability?.reason ?? "Requests go to the configured provider endpoint."
        }
    }

    private func loadAPIKey() {
        apiKey = secretStore.apiKey(for: selectedProvider) ?? ""
    }

    private func saveAPIKey() {
        _ = secretStore.setAPIKey(apiKey, for: selectedProvider)
        Task { await refreshAvailability() }
    }

    private func refreshAvailability() async {
        availability = await WheelModelContextService.shared.availabilityStatus()
    }
}
