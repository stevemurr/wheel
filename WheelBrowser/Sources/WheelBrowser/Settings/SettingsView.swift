import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var contentBlocker = ContentBlockerManager.shared
    @ObservedObject private var blockingStats = BlockingStats.shared
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var showingResetStatsAlert = false

    enum ConnectionStatus {
        case unknown, checking, connected, failed
    }

    var body: some View {
        Form {
            // MARK: - Content Blocking Section
            Section("Privacy & Content Blocking") {
                // Master toggle
                Toggle("Enable Content Blocking", isOn: $settings.adBlockingEnabled)

                // Status indicator
                if contentBlocker.isCompiling {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Compiling blocking rules...")
                            .foregroundColor(.secondary)
                    }
                } else if let error = contentBlocker.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error.localizedDescription)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                } else if contentBlocker.contentRuleList != nil {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text(contentBlocker.statusDescription)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                } else if contentBlocker.enabledCategories.isEmpty {
                    HStack {
                        Image(systemName: "shield.slash")
                            .foregroundColor(.secondary)
                        Text("No blocking categories enabled")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                // Category toggles
                if settings.adBlockingEnabled {
                    DisclosureGroup("Blocking Categories") {
                        ForEach(BlockingCategory.allCases, id: \.self) { category in
                            CategoryToggleRow(
                                category: category,
                                isEnabled: contentBlocker.isEnabled(category),
                                ruleCount: ContentBlockerManager.approximateRuleCounts[category] ?? 0
                            ) {
                                contentBlocker.toggle(category)
                            }
                        }

                        HStack {
                            Button("Enable All") {
                                contentBlocker.enableAll()
                            }
                            .buttonStyle(.borderless)

                            Spacer()

                            Button("Disable All") {
                                contentBlocker.disableAll()
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }

                Button("Refresh Blocking Rules") {
                    Task {
                        await contentBlocker.refreshRules()
                    }
                }
                .disabled(contentBlocker.isCompiling)
            }

            // MARK: - Blocking Statistics Section
            if settings.adBlockingEnabled {
                Section("Blocking Statistics") {
                    StatsRow(
                        icon: "shield.fill",
                        title: "Total Blocked",
                        value: blockingStats.formattedTotalBlocked,
                        subtitle: "Since \(formattedTrackingDate)"
                    )

                    StatsRow(
                        icon: "clock.fill",
                        title: "This Session",
                        value: blockingStats.formattedSessionBlocked,
                        subtitle: nil
                    )

                    StatsRow(
                        icon: "doc.fill",
                        title: "Pages Protected",
                        value: "\(blockingStats.pagesProtected)",
                        subtitle: nil
                    )

                    StatsRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Daily Average",
                        value: blockingStats.formattedAveragePerDay,
                        subtitle: "blocks per day"
                    )

                    // Category breakdown
                    if !blockingStats.blockedByCategory.isEmpty {
                        DisclosureGroup("By Category") {
                            ForEach(BlockingCategory.allCases, id: \.self) { category in
                                HStack {
                                    Image(systemName: category.icon)
                                        .frame(width: 20)
                                        .foregroundColor(.secondary)
                                    Text(category.displayName)
                                    Spacer()
                                    Text(formatCount(blockingStats.blockedByCategory[category] ?? 0))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Button("Reset Statistics", role: .destructive) {
                        showingResetStatsAlert = true
                    }
                    .alert("Reset Statistics", isPresented: $showingResetStatsAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) {
                            blockingStats.resetAllStats()
                        }
                    } message: {
                        Text("This will clear all blocking statistics. This action cannot be undone.")
                    }
                }
            }

            // MARK: - LLM Configuration Section
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
            }

            // MARK: - Letta Server Section
            Section("Letta Server") {
                TextField("Letta Server URL", text: $settings.lettaServerURL)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Status:")
                    switch connectionStatus {
                    case .unknown:
                        Text("Not checked")
                            .foregroundColor(.secondary)
                    case .checking:
                        ProgressView()
                            .scaleEffect(0.7)
                    case .connected:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .failed:
                        Label("Failed", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }

                    Spacer()

                    Button("Test Connection") {
                        testLettaConnection()
                    }
                    .disabled(connectionStatus == .checking)
                }
            }

            // MARK: - Agent Section
            Section("Agent") {
                if settings.agentId.isEmpty {
                    Text("No agent created yet")
                        .foregroundColor(.secondary)
                } else {
                    HStack {
                        Text("Agent ID:")
                        Text(settings.agentId)
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button("Reset Agent", role: .destructive) {
                        settings.agentId = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 650)
        .onAppear {
            fetchModels()
        }
    }

    // MARK: - Helper Properties

    private var formattedTrackingDate: String {
        guard let date = blockingStats.trackingSince else {
            return "today"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    // MARK: - Network Methods

    private func fetchModels() {
        guard let baseURL = settings.llmBaseURL else { return }
        isLoadingModels = true

        let modelsURL = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoadingModels = false

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["models"] as? [[String: Any]] else {
                    return
                }

                availableModels = models.compactMap { $0["name"] as? String }
                if !availableModels.contains(settings.selectedModel) && !availableModels.isEmpty {
                    settings.selectedModel = availableModels[0]
                }
            }
        }.resume()
    }

    private func testLettaConnection() {
        guard let baseURL = settings.lettaBaseURL else {
            connectionStatus = .failed
            return
        }

        connectionStatus = .checking
        let healthURL = baseURL.appendingPathComponent("v1/health")

        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    connectionStatus = .connected
                } else {
                    connectionStatus = .failed
                }
            }
        }.resume()
    }
}

// MARK: - Supporting Views

/// Row for displaying a blocking category with toggle
struct CategoryToggleRow: View {
    let category: BlockingCategory
    let isEnabled: Bool
    let ruleCount: Int
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Image(systemName: category.icon)
                .frame(width: 20)
                .foregroundColor(isEnabled ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                Text("\(ruleCount) rules - \(category.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

/// Row for displaying a statistic
struct StatsRow: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(value)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    SettingsView()
}
