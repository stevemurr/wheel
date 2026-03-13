import SwiftUI

struct LLMSettingsSection: View {
    private enum RemoteModelCatalogState: Equatable {
        case unavailable
        case loading
        case loaded([String])
        case failed(String)
    }

    private static let customModelSelectionTag = "__wheel.customModelID__"

    @AppStorage(AppSettings.aiProviderIDKey) private var providerID = WheelModelProviderID.apple.rawValue
    @AppStorage(AppSettings.aiModelIDKey) private var modelID = WheelModelProviderID.apple.defaultModelID
    @AppStorage(AppSettings.aiBaseURLKey) private var baseURL = ""
    @AppStorage(AppSettings.aiContextWindowOverrideKey) private var contextWindowOverride = 0
    @AppStorage(AppSettings.aiAppleGuardrailsKey) private var appleGuardrails = WheelAppleGuardrailsOption.default.rawValue

    @State private var availability: WheelModelAvailability?
    @State private var apiKey = ""
    @State private var remoteModelCatalogState: RemoteModelCatalogState = .unavailable
    @State private var usesCustomRemoteModelID = false

    private let secretStore: any WheelModelSecretStoring = KeychainWheelModelSecretStore.shared
    private let modelCatalogService = WheelOpenAICompatibleModelCatalogService.shared

    private var selectedProvider: WheelModelProviderID {
        WheelModelProviderID(rawValue: providerID) ?? .apple
    }

    private var profileSummary: String {
        WheelModelConfigurationProvider.shared.currentProfile().displayName
    }

    private var remoteModelOptions: [String] {
        guard case .loaded(let modelIDs) = remoteModelCatalogState else {
            return []
        }
        return modelIDs
    }

    private var showsRemoteModelPicker: Bool {
        selectedProvider.supportsEndpointModelCatalog && remoteModelOptions.isEmpty == false
    }

    private var showsCustomModelIDField: Bool {
        showsRemoteModelPicker && (
            usesCustomRemoteModelID
                || remoteModelOptions.contains(modelID.trimmingCharacters(in: .whitespacesAndNewlines)) == false
        )
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

    private var modelIDSelection: Binding<String> {
        Binding(
            get: {
                let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
                if usesCustomRemoteModelID || remoteModelOptions.contains(trimmedModelID) == false {
                    return Self.customModelSelectionTag
                }
                return trimmedModelID
            },
            set: { newValue in
                if newValue == Self.customModelSelectionTag {
                    usesCustomRemoteModelID = true
                    return
                }
                usesCustomRemoteModelID = false
                modelID = newValue
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

            if showsRemoteModelPicker {
                Picker("Model ID", selection: modelIDSelection) {
                    ForEach(remoteModelOptions, id: \.self) { remoteModelID in
                        Text(remoteModelID).tag(remoteModelID)
                    }
                    Text("Custom...").tag(Self.customModelSelectionTag)
                }
                .pickerStyle(.menu)

                if showsCustomModelIDField {
                    TextField("Custom Model ID", text: $modelID)
                }
            } else {
                TextField("Model ID", text: $modelID)
            }

            if let remoteModelCatalogStatusText {
                HStack(spacing: 8) {
                    if case .loading = remoteModelCatalogState {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(remoteModelCatalogStatusText)
                        .font(.caption)
                        .foregroundColor(remoteModelCatalogStatusColor)
                }
            }

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
            await refreshRemoteModelCatalog()
            await refreshAvailability()
        }
        .onChange(of: providerID) { _, newValue in
            let provider = WheelModelProviderID(rawValue: newValue) ?? .apple
            modelID = provider.defaultModelID
            usesCustomRemoteModelID = false
            loadAPIKey()
            Task {
                await refreshRemoteModelCatalog()
                await refreshAvailability()
            }
        }
        .onChange(of: modelID) { _, _ in
            Task { await refreshAvailability() }
        }
        .onChange(of: baseURL) { _, _ in
            Task {
                await refreshRemoteModelCatalog()
                await refreshAvailability()
            }
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
        Task {
            await refreshRemoteModelCatalog()
            await refreshAvailability()
        }
    }

    private func refreshAvailability() async {
        availability = await WheelModelContextService.shared.availabilityStatus()
    }

    private var remoteModelCatalogStatusText: String? {
        switch remoteModelCatalogState {
        case .unavailable:
            return nil
        case .loading:
            return "Loading models from the endpoint..."
        case .loaded(let modelIDs):
            return modelIDs.isEmpty ? "The configured endpoint did not advertise any models." : nil
        case .failed(let message):
            return message
        }
    }

    private var remoteModelCatalogStatusColor: Color {
        switch remoteModelCatalogState {
        case .failed:
            return .orange
        case .loading, .loaded, .unavailable:
            return .secondary
        }
    }

    @MainActor
    private func refreshRemoteModelCatalog() async {
        guard selectedProvider.supportsEndpointModelCatalog else {
            remoteModelCatalogState = .unavailable
            return
        }

        let provider = selectedProvider
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedAPIKey = secretStore.apiKey(for: provider)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedBaseURL.isEmpty == false else {
            remoteModelCatalogState = .unavailable
            return
        }

        if provider.requiresAPIKey, savedAPIKey?.isEmpty != false {
            remoteModelCatalogState = .unavailable
            return
        }

        remoteModelCatalogState = .loading

        do {
            let modelIDs = try await modelCatalogService.fetchModelIDs(
                for: provider,
                baseURL: trimmedBaseURL,
                apiKey: savedAPIKey
            )
            guard shouldApplyRemoteCatalogResult(
                for: provider,
                baseURL: trimmedBaseURL,
                apiKey: savedAPIKey
            ) else {
                return
            }
            remoteModelCatalogState = .loaded(modelIDs)
        } catch let error as WheelOpenAICompatibleModelCatalogError {
            guard shouldApplyRemoteCatalogResult(
                for: provider,
                baseURL: trimmedBaseURL,
                apiKey: savedAPIKey
            ) else {
                return
            }
            remoteModelCatalogState = .failed(error.localizedDescription)
        } catch {
            guard shouldApplyRemoteCatalogResult(
                for: provider,
                baseURL: trimmedBaseURL,
                apiKey: savedAPIKey
            ) else {
                return
            }
            remoteModelCatalogState = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func shouldApplyRemoteCatalogResult(
        for provider: WheelModelProviderID,
        baseURL: String,
        apiKey: String?
    ) -> Bool {
        provider == selectedProvider
            && baseURL == self.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            && apiKey == secretStore.apiKey(for: provider)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
