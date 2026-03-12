import Fabric
import Foundation

enum WheelFabricAppID {
    static let browser = "wheel.browser"
    static let notes = "wheel.notes"
    static let chat = "wheel.chat"
}

@MainActor
final class WheelBrowserFabricProvider: FabricResourceProvider, FabricSubscriptionProvider {
    let appID = WheelFabricAppID.browser

    private let browserState: BrowserState
    private let contentExtractor: ContentExtractor

    init(browserState: BrowserState, contentExtractor: ContentExtractor) {
        self.browserState = browserState
        self.contentExtractor = contentExtractor
    }

    func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
        var resources: [FabricResourceDescriptor] = browserState.tabs.compactMap { tab in
            guard let url = tab.url?.absoluteString else { return nil }

            return FabricResourceDescriptor(
                uri: FabricURI(appID: appID, kind: "tab", id: tab.id.uuidString),
                kind: "tab",
                title: tab.displayTitle,
                summary: url,
                capabilities: [.read, .mention],
                metadata: [
                    "url": .string(url),
                    "tabID": .string(tab.id.uuidString),
                ],
                presentation: .init(
                    systemImage: "square.on.square",
                    tint: "blue",
                    subtitle: url,
                    categoryLabel: "Tab"
                )
            )
        }

        if let activeTab = browserState.activeTab,
           let url = activeTab.url?.absoluteString {
            resources.insert(
                FabricResourceDescriptor(
                    uri: FabricURI(appID: appID, kind: "page", id: "current"),
                    kind: "page",
                    title: "Current Page",
                    summary: activeTab.displayTitle,
                    capabilities: [.read, .mention, .subscribe],
                    metadata: [
                        "url": .string(url),
                        "tabID": .string(activeTab.id.uuidString),
                    ],
                    presentation: .init(
                        systemImage: "doc.text",
                        tint: "purple",
                        subtitle: url,
                        categoryLabel: "Current"
                    )
                ),
                at: 0
            )

            resources.insert(
                FabricResourceDescriptor(
                    uri: FabricURI(appID: appID, kind: "page-snapshot", id: activeTab.id.uuidString),
                    kind: "page-snapshot",
                    title: "Page Snapshot",
                    summary: activeTab.displayTitle,
                    capabilities: [.read, .mention, .subscribe, .snapshot],
                    metadata: [
                        "url": .string(url),
                        "tabID": .string(activeTab.id.uuidString),
                    ],
                    presentation: .init(
                        systemImage: "camera.viewfinder",
                        tint: "orange",
                        subtitle: url,
                        categoryLabel: "Snapshot"
                    )
                ),
                at: 1
            )
        }

        guard let query, !query.isEmpty else { return resources }
        let loweredQuery = query.lowercased()

        return resources.filter { resource in
            [
                resource.title,
                resource.summary,
                resource.metadata["url"]?.stringValue ?? "",
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(loweredQuery)
        }
    }

    func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        switch uri.kind {
        case "page":
            guard let activeTab = browserState.activeTab else { return nil }
            return await contextPayload(for: activeTab, kind: "page", resourceURI: uri)

        case "page-snapshot":
            guard let tabID = UUID(uuidString: uri.id),
                  let bridge = browserState.bridge(for: tabID) else {
                return nil
            }

            let snapshot = try await bridge.snapshot()
            return FabricContextPayload(
                uri: uri,
                kind: uri.kind,
                title: snapshot.title,
                body: snapshot.textRepresentation,
                metadata: [
                    "url": .string(snapshot.url),
                    "tabID": .string(uri.id),
                ],
                presentation: .init(
                    systemImage: "camera.viewfinder",
                    tint: "orange",
                    subtitle: snapshot.url,
                    categoryLabel: "Snapshot"
                )
            )

        case "tab":
            guard let tabID = UUID(uuidString: uri.id),
                  let tab = browserState.tab(for: tabID) else {
                return nil
            }
            return await contextPayload(for: tab, kind: "tab", resourceURI: uri)

        default:
            return nil
        }
    }

    func validateSubscription(_ request: FabricSubscriptionRequest) async throws {
        if let requestedAppID = request.appID, requestedAppID != appID {
            throw FabricError.unsupportedSubscription("Wheel browser provider only supports \(appID)")
        }
    }

    func currentPageEvent() -> FabricEvent? {
        guard let activeTab = browserState.activeTab,
              let url = activeTab.url?.absoluteString else {
            return nil
        }

        return FabricEvent(
            appID: appID,
            kind: .currentPageChanged,
            resourceURI: FabricURI(appID: appID, kind: "page", id: "current"),
            resourceKind: "page",
            payload: [
                "tabID": .string(activeTab.id.uuidString),
                "title": .string(activeTab.displayTitle),
                "url": .string(url),
            ]
        )
    }

    private func contextPayload(
        for tab: Tab,
        kind: String,
        resourceURI: FabricURI
    ) async -> FabricContextPayload {
        if tab.hasWebView,
           let extracted = await contentExtractor.extractContent(from: tab) {
            return FabricContextPayload(
                uri: resourceURI,
                kind: kind,
                title: extracted.title,
                body: extracted.textContent,
                metadata: [
                    "url": .string(extracted.url),
                    "tabID": .string(tab.id.uuidString),
                ],
                presentation: presentation(for: kind, url: extracted.url)
            )
        }

        let urlString = tab.url?.absoluteString ?? "about:blank"
        return FabricContextPayload(
            uri: resourceURI,
            kind: kind,
            title: tab.displayTitle,
            body: "Title: \(tab.displayTitle)\nURL: \(urlString)",
            metadata: [
                "url": .string(urlString),
                "tabID": .string(tab.id.uuidString),
            ],
            presentation: presentation(for: kind, url: urlString)
        )
    }

    private func presentation(for kind: String, url: String) -> FabricPresentationHints {
        switch kind {
        case "page":
            return .init(
                systemImage: "doc.text",
                tint: "purple",
                subtitle: url,
                categoryLabel: "Current"
            )
        case "page-snapshot":
            return .init(
                systemImage: "camera.viewfinder",
                tint: "orange",
                subtitle: url,
                categoryLabel: "Snapshot"
            )
        default:
            return .init(
                systemImage: "square.on.square",
                tint: "blue",
                subtitle: url,
                categoryLabel: "Tab"
            )
        }
    }
}

@MainActor
final class WheelNotesFabricProvider: FabricResourceProvider, FabricActionProvider, FabricSubscriptionProvider {
    let appID = WheelFabricAppID.notes

    private let noteStore: NoteStore
    private let openNote: (NoteRecord) -> Void

    init(noteStore: NoteStore, openNote: @escaping (NoteRecord) -> Void) {
        self.noteStore = noteStore
        self.openNote = openNote
    }

    func listResources(query: String?) async throws -> [FabricResourceDescriptor] {
        let resources = noteStore.orderedNotes.map { note in
            FabricResourceDescriptor(
                uri: noteURI(for: note.id),
                kind: "note",
                title: note.displayTitle,
                summary: note.excerpt,
                capabilities: [.read, .mention, .subscribe, .open],
                metadata: [
                    "workspaceID": .string(note.workspaceID.uuidString),
                    "noteID": .string(note.id.uuidString),
                ],
                presentation: .init(
                    systemImage: "note.text",
                    tint: "accent",
                    subtitle: note.excerpt,
                    categoryLabel: "Note"
                )
            )
        }

        guard let query, !query.isEmpty else { return resources }
        let loweredQuery = query.lowercased()

        return resources.filter { resource in
            [resource.title, resource.summary]
                .joined(separator: " ")
                .lowercased()
                .contains(loweredQuery)
        }
    }

    func resolveContext(for uri: FabricURI) async throws -> FabricContextPayload? {
        guard uri.kind == "note",
              let noteID = UUID(uuidString: uri.id),
              let note = noteStore.note(with: noteID) else {
            return nil
        }

        return FabricContextPayload(
            uri: uri,
            kind: uri.kind,
            title: note.displayTitle,
            body: note.document.plainText(maxLength: Int.max),
            metadata: [
                "workspaceID": .string(note.workspaceID.uuidString),
                "noteID": .string(note.id.uuidString),
            ],
            presentation: .init(
                systemImage: "note.text",
                tint: "accent",
                subtitle: note.excerpt,
                categoryLabel: "Note"
            )
        )
    }

    func listActions() async throws -> [FabricActionDescriptor] {
        [
            FabricActionDescriptor(
                id: "wheel.notes.create-note",
                appID: appID,
                name: "create-note",
                title: "Create Note",
                summary: "Create a new note in Wheel's notes workspace.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "title": "string",
                        "body": "string",
                    ],
                ],
                isMutation: true,
                requiresConfirmation: true
            ),
            FabricActionDescriptor(
                id: "wheel.notes.append-to-note",
                appID: appID,
                name: "append-to-note",
                title: "Append To Note",
                summary: "Append plaintext content to an existing Wheel note.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "noteURI": "string",
                        "content": "string",
                    ],
                ],
                isMutation: true,
                requiresConfirmation: true
            ),
            FabricActionDescriptor(
                id: "wheel.notes.open-note",
                appID: appID,
                name: "open-note",
                title: "Open Note",
                summary: "Open a Wheel note in the floating note window.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "noteURI": "string",
                    ],
                ],
                isMutation: false,
                requiresConfirmation: false
            ),
        ]
    }

    func invoke(_ invocation: FabricActionInvocation) async throws -> FabricActionResult {
        switch invocation.actionID {
        case "wheel.notes.create-note":
            let title = invocation.arguments["title"]?.stringValue ?? ""
            let body = invocation.arguments["body"]?.stringValue ?? ""
            let note = noteStore.createNote(title: title)

            if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let updatedDocument = note.document.appendingPlainText(body)
                noteStore.updateDocument(id: note.id, document: updatedDocument)
            }

            let resolvedNote = noteStore.note(with: note.id) ?? note
            let createdURI = noteURI(for: resolvedNote.id)
            return FabricActionResult(
                success: true,
                message: "Created note '\(resolvedNote.displayTitle)'",
                output: [
                    "noteURI": .string(createdURI.rawValue),
                    "title": .string(resolvedNote.displayTitle),
                ],
                createdResources: [createdURI]
            )

        case "wheel.notes.append-to-note":
            guard let noteURIString = invocation.arguments["noteURI"]?.stringValue,
                  let content = invocation.arguments["content"]?.stringValue else {
                throw FabricError.invalidURI("Missing noteURI or content")
            }

            let parsedURI = try FabricURI(string: noteURIString)
            guard parsedURI.appID == appID,
                  parsedURI.kind == "note",
                  let noteID = UUID(uuidString: parsedURI.id),
                  let note = noteStore.note(with: noteID) else {
                throw FabricError.resourceNotFound(noteURIString)
            }

            let updatedDocument = note.document.appendingPlainText(content)
            noteStore.updateDocument(id: note.id, document: updatedDocument)
            let resolvedNote = noteStore.note(with: note.id) ?? note
            let updatedURI = noteURI(for: resolvedNote.id)

            return FabricActionResult(
                success: true,
                message: "Updated note '\(resolvedNote.displayTitle)'",
                output: [
                    "noteURI": .string(updatedURI.rawValue),
                    "title": .string(resolvedNote.displayTitle),
                ],
                updatedResources: [updatedURI]
            )

        case "wheel.notes.open-note":
            guard let noteURIString = invocation.arguments["noteURI"]?.stringValue else {
                throw FabricError.invalidURI("Missing noteURI")
            }

            let parsedURI = try FabricURI(string: noteURIString)
            guard parsedURI.appID == appID,
                  parsedURI.kind == "note",
                  let noteID = UUID(uuidString: parsedURI.id),
                  let note = noteStore.note(with: noteID) else {
                throw FabricError.resourceNotFound(noteURIString)
            }

            openNote(note)
            return FabricActionResult(
                success: true,
                message: "Opened note '\(note.displayTitle)'",
                output: [
                    "noteURI": .string(parsedURI.rawValue),
                    "title": .string(note.displayTitle),
                ]
            )

        default:
            throw FabricError.actionNotFound(invocation.actionID)
        }
    }

    func validateSubscription(_ request: FabricSubscriptionRequest) async throws {
        if let requestedAppID = request.appID, requestedAppID != appID {
            throw FabricError.unsupportedSubscription("Wheel notes provider only supports \(appID)")
        }
    }

    func noteEvent(for change: NoteStoreChange) -> FabricEvent {
        switch change {
        case .created(let note), .updated(let note):
            return FabricEvent(
                appID: appID,
                kind: .resourceUpdated,
                resourceURI: noteURI(for: note.id),
                resourceKind: "note",
                payload: [
                    "title": .string(note.displayTitle),
                    "workspaceID": .string(note.workspaceID.uuidString),
                    "noteID": .string(note.id.uuidString),
                ]
            )

        case .deleted(let noteID, let workspaceID):
            return FabricEvent(
                appID: appID,
                kind: .resourceRemoved,
                resourceURI: noteURI(for: noteID),
                resourceKind: "note",
                payload: [
                    "workspaceID": .string(workspaceID.uuidString),
                    "noteID": .string(noteID.uuidString),
                ]
            )
        }
    }

    private func noteURI(for noteID: UUID) -> FabricURI {
        FabricURI(appID: appID, kind: "note", id: noteID.uuidString)
    }
}

@MainActor
final class WheelFabricCoordinator {
    private let browserProvider: WheelBrowserFabricProvider
    private let notesProvider: WheelNotesFabricProvider
    private let browserClient: FabricXPCClient
    private let notesClient: FabricXPCClient
    let consumerClient: FabricXPCClient

    private var isRegistered = false
    private var isRegistering = false

    init(
        browserState: BrowserState,
        noteStore: NoteStore,
        contentExtractor: ContentExtractor,
        openNote: @escaping (NoteRecord) -> Void
    ) {
        self.browserProvider = WheelBrowserFabricProvider(
            browserState: browserState,
            contentExtractor: contentExtractor
        )
        self.notesProvider = WheelNotesFabricProvider(
            noteStore: noteStore,
            openNote: openNote
        )
        self.browserClient = FabricXPCClient(
            resourceProvider: AnyFabricResourceProvider(browserProvider),
            actionProvider: nil,
            subscriptionProvider: AnyFabricSubscriptionProvider(browserProvider)
        )
        self.notesClient = FabricXPCClient(
            resourceProvider: AnyFabricResourceProvider(notesProvider),
            actionProvider: AnyFabricActionProvider(notesProvider),
            subscriptionProvider: AnyFabricSubscriptionProvider(notesProvider)
        )
        self.consumerClient = FabricXPCClient()
    }

    func start() {
        guard !isRegistered, !isRegistering else { return }
        isRegistering = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isRegistering = false }

            do {
                try await browserClient.register(
                    appID: browserProvider.appID,
                    exposesResources: true,
                    exposesActions: false,
                    exposesSubscriptions: true
                )
                try await notesClient.register(
                    appID: notesProvider.appID,
                    exposesResources: true,
                    exposesActions: true,
                    exposesSubscriptions: true
                )
                isRegistered = true
                Log.Services.info("Fabric providers registered")
                await publishCurrentPageChange()
            } catch {
                isRegistered = false
                Log.Services.warning("Fabric registration failed: \(error.localizedDescription)")
            }
        }
    }

    func publishCurrentPageChange() async {
        guard isRegistered,
              let event = browserProvider.currentPageEvent() else {
            return
        }

        do {
            try await browserClient.publish(event: event, from: browserProvider.appID)
        } catch {
            Log.Services.warning("Fabric current-page publish failed: \(error.localizedDescription)")
        }
    }

    func publishNoteChange(_ change: NoteStoreChange) async {
        guard isRegistered else { return }

        do {
            try await notesClient.publish(
                event: notesProvider.noteEvent(for: change),
                from: notesProvider.appID
            )
        } catch {
            Log.Services.warning("Fabric note publish failed: \(error.localizedDescription)")
        }
    }
}

private extension NoteDocument {
    func appendingPlainText(_ text: String) -> NoteDocument {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return self }

        var updatedRoot = root
        var content = updatedRoot["content"]?.arrayValue ?? []

        for line in normalized.components(separatedBy: .newlines) {
            if line.isEmpty {
                content.append([
                    "type": AnyCodable("paragraph"),
                    "content": AnyCodable([]),
                ])
            } else {
                content.append([
                    "type": AnyCodable("paragraph"),
                    "content": AnyCodable([
                        [
                            "type": "text",
                            "text": line,
                        ],
                    ]),
                ])
            }
        }

        updatedRoot["content"] = AnyCodable(content)
        return NoteDocument(root: updatedRoot)
    }
}
