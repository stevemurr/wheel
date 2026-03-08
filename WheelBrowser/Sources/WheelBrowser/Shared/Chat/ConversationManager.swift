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
@Observable
class ConversationManager {
    static let shared = ConversationManager()

    private(set) var currentConversation: Conversation?
    private(set) var savedConversations: [Conversation] = []

    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private let saveDebounceInterval: TimeInterval = 2.0

    private var conversationsDirectory: URL {
        let dir = FileManager.appSupportDirectory
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

    @discardableResult
    func activateConversation(
        id: UUID,
        workspaceId: UUID? = nil,
        tabUrl: String? = nil
    ) -> Conversation {
        if let currentConversation, currentConversation.id == id {
            return currentConversation
        }

        if let conversation = conversation(with: id) {
            currentConversation = conversation
            savedConversations.removeAll { $0.id == id }
            return conversation
        }

        let conversation = Conversation(
            id: id,
            workspaceId: workspaceId,
            associatedTabUrl: tabUrl
        )
        currentConversation = conversation
        return conversation
    }

    func conversation(with id: UUID) -> Conversation? {
        if let currentConversation, currentConversation.id == id {
            return currentConversation
        }

        if let savedConversation = savedConversations.first(where: { $0.id == id }) {
            return savedConversation
        }

        let fileURL = conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Conversation.self, from: data)
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

    func replaceMessages(_ messages: [ChatMessage], conversationID: UUID) {
        let existing = activateConversation(id: conversationID)
        var updated = existing
        updated.messages = messages
        updated.updatedAt = Date()
        if updated.title == "New Conversation",
           let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let title = String(firstUserMessage.content.prefix(50))
            updated.title = title.count < firstUserMessage.content.count ? title + "..." : title
        }

        currentConversation = updated
        savedConversations.removeAll { $0.id == conversationID }
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
        pendingSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard let conversation = currentConversation else { return }
            saveConversationImmediately(conversation)
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            savedConversations = await Self.loadConversations(from: dir)
        }
    }

    nonisolated private static func loadConversations(from directory: URL) async -> [Conversation] {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var loaded: [Conversation] = []

            if let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
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

            loaded.sort { $0.updatedAt > $1.updatedAt }
            return loaded
        }.value
    }
}
