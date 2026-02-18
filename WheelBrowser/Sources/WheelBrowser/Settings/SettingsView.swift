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
    @State private var showingClearIndexAlert = false
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey = false
    @State private var llmConnectionStatus: LLMConnectionStatus = .unknown

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

            // MARK: - Semantic Search Section
            Section("Semantic Search") {
                Toggle("Enable Semantic Search", isOn: $settings.semanticSearchEnabled)

                Text("Index your browsing history for semantic search. Uses embeddings to find pages by meaning, not just keywords.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Embedding Provider", selection: $settings.embeddingProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Voyage AI").tag("voyage")
                    Text("Local (macOS)").tag("local")
                    Text("Custom").tag("custom")
                }

                if settings.embeddingProvider == "local" {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Local embeddings have lower quality than API-based options")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if settings.embeddingProvider == "custom" {
                    TextField("Endpoint URL", text: $settings.embeddingEndpoint)
                        .textFieldStyle(.roundedBorder)
                }

                if settings.embeddingProvider != "local" {
                    TextField("Model", text: $settings.embeddingModel)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("Dimensions")
                        Spacer()
                        TextField("", value: $settings.embeddingDimensions, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    Text("Changing dimensions will clear the search index")
                        .font(.caption2)
                        .foregroundColor(.orange)

                    // API Key
                    EmbeddingAPIKeyField(settings: settings)
                }

                // Presets
                if settings.embeddingProvider == "openai" {
                    HStack {
                        Text("Presets:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Small (1536d)") {
                            settings.embeddingModel = "text-embedding-3-small"
                            settings.embeddingDimensions = 1536
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)

                        Button("Large (3072d)") {
                            settings.embeddingModel = "text-embedding-3-large"
                            settings.embeddingDimensions = 3072
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                if settings.embeddingProvider == "voyage" {
                    HStack {
                        Text("Presets:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Lite (512d)") {
                            settings.embeddingModel = "voyage-3-lite"
                            settings.embeddingDimensions = 512
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)

                        Button("Standard (1024d)") {
                            settings.embeddingModel = "voyage-3"
                            settings.embeddingDimensions = 1024
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }

                // Index stats
                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: semanticSearch.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(semanticSearch.isAvailable ? .green : .red)
                            Text(semanticSearch.isAvailable ? "Search available" : "Search unavailable")
                                .font(.caption)
                        }

                        HStack(spacing: 16) {
                            Label("\(semanticSearch.indexedCount) indexed", systemImage: "doc.text.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if semanticSearch.pendingCount > 0 {
                                Label("\(semanticSearch.pendingCount) pending", systemImage: "clock.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            if semanticSearch.isIndexing {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }

                        if let error = semanticSearch.lastError {
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    Button("Clear Index", role: .destructive) {
                        showingClearIndexAlert = true
                    }
                    .buttonStyle(.borderless)
                }
                .alert("Clear Search Index", isPresented: $showingClearIndexAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Clear", role: .destructive) {
                        Task {
                            await semanticSearch.clearIndex()
                        }
                    }
                } message: {
                    Text("This will delete all indexed pages. They will be re-indexed as you browse.")
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
        .frame(width: 500, height: 800)
        .onAppear {
            fetchModels()
            // Load the existing API key from Keychain into the input field
            apiKeyInput = settings.llmAPIKey
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

/// Field for entering embedding API key
struct EmbeddingAPIKeyField: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if showAPIKey {
                    TextField("Embedding API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField("Embedding API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                }

                Button(action: { showAPIKey.toggle() }) {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)

                Button("Save") {
                    settings.embeddingAPIKey = apiKeyInput
                }
                .disabled(apiKeyInput.isEmpty)
            }

            if settings.hasEmbeddingAPIKey {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("API key configured")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Clear", role: .destructive) {
                        settings.embeddingAPIKey = ""
                        apiKeyInput = ""
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }

            Text("API key is stored securely in your system Keychain")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .onAppear {
            apiKeyInput = settings.embeddingAPIKey
        }
    }
}

#Preview {
    SettingsView()
}
