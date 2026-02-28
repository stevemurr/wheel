import SwiftUI

struct LLMSettingsSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey = false
    @State private var connectionStatus: ConnectionStatus = .unknown

    var body: some View {
        Section("LLM Configuration") {
            TextField("LLM Endpoint", text: $settings.llmEndpoint)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker("Model", selection: $settings.selectedModel) {
                    if availableModels.isEmpty {
                        Text(settings.selectedModel).tag(settings.selectedModel)
                    } else {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                Button(action: fetchModels) {
                    if isLoadingModels {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoadingModels)
            }

            // API Key toggle
            Toggle("Use API Key Authentication", isOn: $settings.useAPIKey)

            // API Key input field (only shown when toggle is on)
            if settings.useAPIKey {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if showAPIKey {
                            TextField("API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(showAPIKey ? "Hide API key" : "Show API key")

                        Button("Save") {
                            settings.llmAPIKey = apiKeyInput
                        }
                        .disabled(apiKeyInput.isEmpty)
                    }

                    if settings.hasAPIKey {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("API key configured")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button("Clear", role: .destructive) {
                                settings.llmAPIKey = ""
                                apiKeyInput = ""
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("No API key configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("API key is stored securely in your system Keychain")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Connection test
            HStack {
                switch connectionStatus {
                case .unknown:
                    Text("Connection not tested")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .checking:
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Testing connection...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .connected:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connected to LLM endpoint")
                        .font(.caption)
                        .foregroundColor(.green)
                case .failed(let message):
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }

                Spacer()

                Button("Test Connection") {
                    testConnection()
                }
                .disabled(connectionStatus.isChecking)
            }
        }
        .onAppear {
            fetchModels()
            apiKeyInput = settings.llmAPIKey
        }
    }

    // MARK: - Network Methods

    private func fetchModels() {
        guard let baseURL = settings.llmBaseURL else { return }
        isLoadingModels = true

        let modelsURL = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"

        // Add API key if enabled
        if settings.useAPIKey && settings.hasAPIKey {
            request.setValue("Bearer \(settings.llmAPIKey)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoadingModels = false

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }

                // Handle both Ollama format ({"models": [...]}) and OpenAI format ({"data": [...]})
                if let models = json["models"] as? [[String: Any]] {
                    // Ollama format
                    availableModels = models.compactMap { $0["name"] as? String }
                } else if let data = json["data"] as? [[String: Any]] {
                    // OpenAI format
                    availableModels = data.compactMap { $0["id"] as? String }
                }

                if !availableModels.contains(settings.selectedModel) && !availableModels.isEmpty {
                    settings.selectedModel = availableModels[0]
                }
            }
        }.resume()
    }

    private func testConnection() {
        guard let baseURL = settings.llmBaseURL else {
            connectionStatus = .failed("Invalid endpoint URL")
            return
        }

        connectionStatus = .checking

        // Use the models endpoint to test the connection
        let modelsURL = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        // Add API key if enabled
        if settings.useAPIKey && settings.hasAPIKey {
            request.setValue("Bearer \(settings.llmAPIKey)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    connectionStatus = .failed(error.localizedDescription)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    connectionStatus = .failed("Invalid response")
                    return
                }

                switch httpResponse.statusCode {
                case 200:
                    connectionStatus = .connected
                case 401:
                    connectionStatus = .failed("Unauthorized - check API key")
                case 403:
                    connectionStatus = .failed("Forbidden - invalid API key")
                default:
                    connectionStatus = .failed("HTTP \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
}
