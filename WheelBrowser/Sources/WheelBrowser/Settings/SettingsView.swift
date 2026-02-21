import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var contentBlocker = ContentBlockerManager.shared
    @ObservedObject private var blockingStats = BlockingStats.shared
    @ObservedObject private var semanticSearch = SemanticSearchManagerV2.shared
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var showingResetStatsAlert = false
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey = false
    @State private var llmConnectionStatus: LLMConnectionStatus = .unknown
    @State private var dindexConnectionStatus: DIndexConnectionStatus = .unknown
    @State private var dindexAPIKeyInput: String = ""
    @State private var showDIndexAPIKey = false

    enum ConnectionStatus {
        case unknown, checking, connected, failed
    }

    enum LLMConnectionStatus {
        case unknown, checking, connected, failed(String)

        var isChecking: Bool {
            if case .checking = self { return true }
            return false
        }
    }

    enum DIndexConnectionStatus {
        case unknown, checking, connected, failed(String)

        var isChecking: Bool {
            if case .checking = self { return true }
            return false
        }
    }

    var body: some View {
        Form {
            // MARK: - Appearance Section
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // MARK: - Dark Mode for Web Content Section
            Section("Dark Mode (Web Content)") {
                Picker("Mode", selection: $settings.darkModeMode) {
                    ForEach(DarkModeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Inverts page colors while preserving images and videos. Similar to Dark Reader extension.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Brightness slider
                HStack {
                    Image(systemName: "sun.min")
                        .foregroundColor(.secondary)
                    Slider(value: $settings.darkModeBrightness, in: 50...150, step: 5)
                    Image(systemName: "sun.max")
                        .foregroundColor(.secondary)
                    Text("\(Int(settings.darkModeBrightness))%")
                        .frame(width: 45, alignment: .trailing)
                        .foregroundColor(.secondary)
                }

                // Contrast slider
                HStack {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundColor(.secondary)
                    Slider(value: $settings.darkModeContrast, in: 50...150, step: 5)
                    Image(systemName: "circle.righthalf.filled")
                        .foregroundColor(.secondary)
                    Text("\(Int(settings.darkModeContrast))%")
                        .frame(width: 45, alignment: .trailing)
                        .foregroundColor(.secondary)
                }

                // Reset to defaults button
                if settings.darkModeBrightness != 100 || settings.darkModeContrast != 100 {
                    Button("Reset to Defaults") {
                        settings.darkModeBrightness = 100
                        settings.darkModeContrast = 100
                    }
                    .buttonStyle(.borderless)
                }
            }

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

            // MARK: - External Filter Lists Section
            if settings.adBlockingEnabled {
                Section("External Filter Lists") {
                    FilterListSettingsView()
                }
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
                    switch llmConnectionStatus {
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
                        testLLMConnection()
                    }
                    .disabled(llmConnectionStatus.isChecking)
                }
            }

            // MARK: - Semantic Search (DIndex) Section
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
                            if showDIndexAPIKey {
                                TextField("API Key (optional)", text: $dindexAPIKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("API Key (optional)", text: $dindexAPIKeyInput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: { showDIndexAPIKey.toggle() }) {
                                Image(systemName: showDIndexAPIKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)

                            Button("Save") {
                                settings.dindexAPIKey = dindexAPIKeyInput
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
                                    dindexAPIKeyInput = ""
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Divider()

                    // Connection status
                    HStack {
                        switch dindexConnectionStatus {
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
                            testDIndexConnection()
                        }
                        .disabled(dindexConnectionStatus.isChecking)
                    }
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

            // MARK: - MCP Server Section
            Section("MCP Server") {
                MCPSettingsView()
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 900)
        .onAppear {
            fetchModels()
            // Load the existing API key from Keychain into the input field
            apiKeyInput = settings.llmAPIKey
            // Load DIndex API key
            dindexAPIKeyInput = settings.dindexAPIKey
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

    private func testLLMConnection() {
        guard let baseURL = settings.llmBaseURL else {
            llmConnectionStatus = .failed("Invalid endpoint URL")
            return
        }

        llmConnectionStatus = .checking

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
                    llmConnectionStatus = .failed(error.localizedDescription)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    llmConnectionStatus = .failed("Invalid response")
                    return
                }

                switch httpResponse.statusCode {
                case 200:
                    llmConnectionStatus = .connected
                case 401:
                    llmConnectionStatus = .failed("Unauthorized - check API key")
                case 403:
                    llmConnectionStatus = .failed("Forbidden - invalid API key")
                default:
                    llmConnectionStatus = .failed("HTTP \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }

    private func testDIndexConnection() {
        guard let endpointURL = URL(string: settings.dindexEndpoint) else {
            dindexConnectionStatus = .failed("Invalid endpoint URL")
            return
        }

        dindexConnectionStatus = .checking

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
                    dindexConnectionStatus = .failed(error.localizedDescription)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    dindexConnectionStatus = .failed("Invalid response")
                    return
                }

                switch httpResponse.statusCode {
                case 200:
                    // Parse the health response
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let healthy = json["healthy"] as? Bool,
                       healthy {
                        dindexConnectionStatus = .connected
                        // Trigger re-initialization to connect
                        Task {
                            await semanticSearch.reinitialize()
                        }
                    } else {
                        dindexConnectionStatus = .failed("Server unhealthy")
                    }
                case 401:
                    dindexConnectionStatus = .failed("Unauthorized - check API key")
                case 403:
                    dindexConnectionStatus = .failed("Forbidden - invalid API key")
                default:
                    dindexConnectionStatus = .failed("HTTP \(httpResponse.statusCode)")
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
