import SwiftUI

struct DIndexSettingsSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var semanticSearch = SemanticSearchManagerV2.shared
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey = false

    var body: some View {
        Section("Semantic Search") {
            Toggle("Enable Semantic Search", isOn: $settings.dindexEnabled)

            Text("Index your browsing history for semantic search. Uses DIndex to find pages by meaning, not just keywords. Supports @Web, @History, @ReadingList mentions.")
                .font(.caption)
                .foregroundColor(.secondary)

            if settings.dindexEnabled {
                TextField("Endpoint URL", text: $settings.dindexEndpoint)
                    .textFieldStyle(.roundedBorder)

                // API Key (optional)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if showAPIKey {
                            TextField("API Key (optional)", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("API Key (optional)", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)

                        Button("Save") {
                            settings.dindexAPIKey = apiKeyInput
                        }
                    }

                    if !settings.dindexAPIKey.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("API key configured")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button("Clear", role: .destructive) {
                                settings.dindexAPIKey = ""
                                apiKeyInput = ""
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Divider()

                // Connection status
                HStack {
                    switch connectionStatus {
                    case .unknown:
                        if semanticSearch.isDIndexConnected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Connection not tested")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .checking:
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Testing connection...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .connected:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected to DIndex")
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
        }
        .onAppear {
            apiKeyInput = settings.dindexAPIKey
        }
    }

    // MARK: - Network Methods

    private func testConnection() {
        guard let endpointURL = URL(string: settings.dindexEndpoint) else {
            connectionStatus = .failed("Invalid endpoint URL")
            return
        }

        connectionStatus = .checking

        let healthURL = endpointURL.appendingPathComponent("api/v1/health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        // Add API key if configured
        if !settings.dindexAPIKey.isEmpty {
            request.setValue("Bearer \(settings.dindexAPIKey)", forHTTPHeaderField: "Authorization")
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
                    // Parse the health response
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let healthy = json["healthy"] as? Bool,
                       healthy {
                        connectionStatus = .connected
                        // Trigger re-initialization to connect
                        Task {
                            await semanticSearch.reinitialize()
                        }
                    } else {
                        connectionStatus = .failed("Server unhealthy")
                    }
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
