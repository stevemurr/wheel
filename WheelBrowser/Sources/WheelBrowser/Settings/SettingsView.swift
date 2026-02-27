import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var contentBlocker = ContentBlockerManager.shared
    @ObservedObject private var filterListManager = FilterListManager.shared
    @ObservedObject private var semanticSearch = SemanticSearchManagerV2.shared
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var apiKeyInput: String = ""
    @State private var showAPIKey = false
    @State private var llmConnectionStatus: LLMConnectionStatus = .unknown
    @State private var dindexConnectionStatus: DIndexConnectionStatus = .unknown
    @State private var dindexAPIKeyInput: String = ""
    @State private var showDIndexAPIKey = false

    // Debug section state
    @State private var showClearHistoryAlert = false
    @State private var showClearReadingListAlert = false
    @State private var showClearSemanticIndexAlert = false

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
            Section("Content Blocking") {
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

                // All blocking options in one flat list
                if settings.adBlockingEnabled {
                    // Built-in blocking categories
                    ForEach(BlockingCategory.allCases, id: \.self) { category in
                        CategoryToggleRow(
                            category: category,
                            isEnabled: contentBlocker.isEnabled(category),
                            ruleCount: ContentBlockerManager.approximateRuleCounts[category] ?? 0
                        ) {
                            contentBlocker.toggle(category)
                        }
                    }

                    // Built-in filter lists (EasyList, EasyPrivacy)
                    ForEach(filterListManager.filterLists.filter { $0.isBuiltIn }) { filterList in
                        FilterListToggleRow(filterList: filterList)
                    }
                }

                Button("Refresh Blocking Rules") {
                    Task {
                        await contentBlocker.refreshRules()
                    }
                }
                .disabled(contentBlocker.isCompiling)
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

            // MARK: - Debug Section
            Section("Debug") {
                Button(role: .destructive) {
                    showClearHistoryAlert = true
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .frame(width: 20)
                        Text("Clear Browsing History")
                    }
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    showClearReadingListAlert = true
                } label: {
                    HStack {
                        Image(systemName: "bookmark.slash")
                            .frame(width: 20)
                        Text("Clear Reading List")
                    }
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    showClearSemanticIndexAlert = true
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 20)
                        Text("Clear Semantic Index")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 900)
        .alert("Clear Browsing History?", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                BrowsingHistory.shared.clearHistory()
            }
        } message: {
            Text("This will permanently delete all browsing history. This action cannot be undone.")
        }
        .alert("Clear Reading List?", isPresented: $showClearReadingListAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    do {
                        let database = SearchDatabase.shared
                        try await database.initialize()
                        try await database.clearReadingList()
                    } catch {
                        Log.Settings.error("Failed to clear reading list: \(error.localizedDescription)")
                    }
                }
            }
        } message: {
            Text("This will remove all items from your reading list. This action cannot be undone.")
        }
        .alert("Clear Semantic Index?", isPresented: $showClearSemanticIndexAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    do {
                        // Clear local SearchDatabase
                        let database = SearchDatabase.shared
                        try await database.initialize()
                        try await database.clearAllData()

                        // Clear remote DIndex server
                        await SemanticSearchManagerV2.shared.clearIndex()
                    } catch {
                        Log.Settings.error("Failed to clear semantic index: \(error.localizedDescription)")
                    }
                }
            }
        } message: {
            Text("This will delete all indexed page data used for semantic search. This action cannot be undone.")
        }
        .onAppear {
            fetchModels()
            // Load the existing API key from Keychain into the input field
            apiKeyInput = settings.llmAPIKey
            // Load DIndex API key
            dindexAPIKeyInput = settings.dindexAPIKey
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

/// Row for displaying a filter list with toggle (matching CategoryToggleRow style)
struct FilterListToggleRow: View {
    let filterList: FilterList
    @ObservedObject private var manager = FilterListManager.shared

    var body: some View {
        HStack {
            Image(systemName: "list.bullet.rectangle")
                .frame(width: 20)
                .foregroundColor(filterList.isEnabled ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(filterList.name)
                if filterList.ruleCount > 0 {
                    Text("\(formatRuleCount(filterList.ruleCount)) rules - Community filter list")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Community filter list")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { filterList.isEnabled },
                set: { newValue in
                    manager.setEnabled(newValue, for: filterList)
                }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            manager.toggleFilterList(filterList)
        }
    }

    private func formatRuleCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}

// MARK: - External Filter Lists View (Inline)

/// Inline view for external filter lists within the Content Blocking section
struct ExternalFilterListsView: View {
    @ObservedObject private var manager = FilterListManager.shared
    @State private var showingAddSheet = false
    @State private var newListURL = ""
    @State private var newListName = ""
    @State private var urlError: String?

    var body: some View {
        DisclosureGroup {
            // Progress bar during update
            if manager.isUpdating {
                ProgressView(value: manager.updateProgress)
                    .progressViewStyle(.linear)
            }

            // Filter list rows
            ForEach(manager.filterLists) { filterList in
                ExternalFilterListRow(filterList: filterList)
            }

            // Add button
            Button(action: { showingAddSheet = true }) {
                Label("Add Filter List", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)

            // WebKit limit warning
            if manager.totalEnabledRuleCount > 45_000 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Approaching WebKit's 50,000 rule limit. Some rules may be truncated.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .frame(width: 20)
                    .foregroundColor(manager.enabledCount > 0 ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("External Filter Lists")
                    Text("\(manager.enabledCount) enabled, \(formatRuleCount(manager.totalEnabledRuleCount)) rules")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Update all button
                Button(action: {
                    Task {
                        await manager.updateAll(forceUpdate: true)
                    }
                }) {
                    if manager.isUpdating {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(manager.isUpdating)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddFilterListSheet(
                url: $newListURL,
                name: $newListName,
                error: $urlError,
                onAdd: addFilterList,
                onCancel: { showingAddSheet = false }
            )
        }
    }

    private func formatRuleCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }

    private func addFilterList() {
        guard let url = URL(string: newListURL),
              url.scheme == "http" || url.scheme == "https" else {
            urlError = "Please enter a valid HTTP(S) URL"
            return
        }

        let name = newListName.isEmpty ? url.lastPathComponent : newListName

        manager.addFilterList(name: name, url: url)

        // Fetch the new list
        Task {
            if let addedList = manager.filterLists.last {
                _ = try? await manager.updateFilterList(addedList, forceUpdate: true)
            }
        }

        // Reset and close
        newListURL = ""
        newListName = ""
        urlError = nil
        showingAddSheet = false
    }
}

// MARK: - External Filter List Row

struct ExternalFilterListRow: View {
    let filterList: FilterList
    @ObservedObject private var manager = FilterListManager.shared
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Enable toggle
            Toggle("", isOn: Binding(
                get: { filterList.isEnabled },
                set: { _ in manager.toggleFilterList(filterList) }
            ))
            .labelsHidden()

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(filterList.name)
                        .fontWeight(.medium)

                    if filterList.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }

                    if filterList.lastError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }

                HStack(spacing: 8) {
                    if filterList.ruleCount > 0 {
                        Text("\(formatRuleCount(filterList.ruleCount)) rules")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let lastUpdated = filterList.lastUpdated {
                        Text("Updated \(formatRelativeDate(lastUpdated))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if filterList.isEnabled {
                        Text("Not downloaded")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                if let error = filterList.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Delete button (for non-built-in lists)
            if !filterList.isBuiltIn {
                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .alert("Remove Filter List?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                manager.removeFilterList(filterList)
            }
        } message: {
            Text("This will remove \"\(filterList.name)\" and its rules.")
        }
    }

    private func formatRuleCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    SettingsView()
}
