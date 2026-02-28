import Foundation

/// Represents a saved conversation
struct Conversation: Codable, Identifiable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var workspaceId: UUID?
    var associatedTabUrl: String?
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        workspaceId: UUID? = nil,
        associatedTabUrl: String? = nil,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.workspaceId = workspaceId
        self.associatedTabUrl = associatedTabUrl
        self.messages = messages
    }
}

/// Manages conversation persistence to disk with debounced saves
@MainActor
class ConversationManager: ObservableObject {
    static let shared = ConversationManager()

    @Published private(set) var currentConversation: Conversation?
    @Published private(set) var savedConversations: [Conversation] = []

    private var pendingSaveTask: Task<Void, Never>?
    private let saveDebounceInterval: TimeInterval = 2.0

    private var conversationsDirectory: URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("WheelBrowser/Conversations")
        }
        let dir = appSupport
            .appendingPathComponent("WheelBrowser", isDirectory: true)
            .appendingPathComponent("Conversations", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        loadConversationsAsync()
    }

    // MARK: - Public API

    /// Start a new conversation
    func startConversation(workspaceId: UUID? = nil, tabUrl: String? = nil) -> Conversation {
        let conversation = Conversation(
            workspaceId: workspaceId,
            associatedTabUrl: tabUrl
        )
        currentConversation = conversation
        return conversation
    }

    /// Add a message to the current conversation, creating one if needed
    func addMessage(_ message: ChatMessage) {
        if currentConversation == nil {
            currentConversation = Conversation()
        }

        currentConversation?.messages.append(message)
        currentConversation?.updatedAt = Date()

        // Auto-title from first user message
        if currentConversation?.title == "New Conversation",
           message.role == .user {
            let title = String(message.content.prefix(50))
            currentConversation?.title = title.count < message.content.count ? title + "..." : title
        }

        scheduleDebouncedSave()
    }

    /// Update a message at the given index
    func updateMessage(at index: Int, update: (inout ChatMessage) -> Void) {
        guard var conversation = currentConversation,
              conversation.messages.indices.contains(index) else { return }
        update(&conversation.messages[index])
        conversation.updatedAt = Date()
        currentConversation = conversation
        scheduleDebouncedSave()
    }

    /// Get messages for the current conversation
    var messages: [ChatMessage] {
        currentConversation?.messages ?? []
    }

    /// Clear current conversation
    func clearCurrentConversation() {
        if let conversation = currentConversation {
            // Save before clearing so it's persisted
            saveConversationImmediately(conversation)
        }
        currentConversation = nil
    }

    /// Resume a previous conversation
    func resumeConversation(_ conversation: Conversation) {
        // Save current if exists
        if let current = currentConversation {
            saveConversationImmediately(current)
        }
        currentConversation = conversation
        // Remove from saved list since it's now active
        savedConversations.removeAll { $0.id == conversation.id }
    }

    /// Delete a saved conversation
    func deleteConversation(_ id: UUID) {
        savedConversations.removeAll { $0.id == id }
        let fileURL = conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Force save the current conversation immediately
    func saveCurrentConversation() {
        guard let conversation = currentConversation else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        saveConversationImmediately(conversation)
    }

    // MARK: - Private

    private func scheduleDebouncedSave() {
        pendingSaveTask?.cancel()
        let interval = saveDebounceInterval
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if let conversation = await self?.currentConversation {
                await self?.saveConversationImmediately(conversation)
            }
        }
    }

    private func saveConversationImmediately(_ conversation: Conversation) {
        let fileURL = conversationsDirectory.appendingPathComponent("\(conversation.id.uuidString).json")
        Task.detached {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(conversation)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Log.Chat.error("Failed to save conversation: \(error.localizedDescription)")
            }
        }
    }

    private func loadConversationsAsync() {
        let dir = conversationsDirectory
        Task.detached { [weak self] in
            guard FileManager.default.fileExists(atPath: dir.path) else { return }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var loaded: [Conversation] = []

            if let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) {
                for file in files where file.pathExtension == "json" {
                    if let data = try? Data(contentsOf: file),
                       let conversation = try? decoder.decode(Conversation.self, from: data) {
                        loaded.append(conversation)
                    }
                }
            }

            // Sort by most recently updated
            loaded.sort { $0.updatedAt > $1.updatedAt }

            await MainActor.run {
                self?.savedConversations = loaded
            }
        }
    }
}
