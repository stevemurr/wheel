import Fabric
import Foundation
import Testing
@testable import WheelBrowser

@MainActor
@Suite("Mention suggestions")
struct MentionSuggestionsViewModelTests {
    @Test("Unknown Fabric resources appear as generic mentions when the query matches")
    func suggestsGenericFabricResources() async throws {
        let viewModel = MentionSuggestionsViewModel()
        let resourceURI = FabricURI(appID: "external.docs", kind: "document", id: "roadmap")
        viewModel.fabricClient = FabricMentionClientStub(
            resources: [
                FabricResourceDescriptor(
                    uri: resourceURI,
                    kind: "document",
                    title: "Platform Roadmap",
                    summary: "Q3 planning document",
                    capabilities: [.read, .mention],
                    presentation: .init(
                        systemImage: "doc.richtext",
                        tint: "gray",
                        subtitle: "Q3 planning document",
                        categoryLabel: "Document"
                    )
                )
            ]
        )

        viewModel.updateSuggestions(for: "roadmap", excluding: [], currentTabId: nil)

        for _ in 0..<20 {
            if viewModel.suggestions.contains(where: {
                if case .fabricResource(let reference) = $0.mention {
                    return reference.uri == resourceURI
                        && reference.title == "Platform Roadmap"
                        && reference.presentation?.categoryLabel == "Document"
                }
                return false
            }) {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(
            viewModel.suggestions.contains {
                if case .fabricResource(let reference) = $0.mention {
                    return reference.uri == resourceURI
                        && reference.title == "Platform Roadmap"
                        && reference.presentation?.systemImage == "doc.richtext"
                }
                return false
            }
        )
    }

    @Test("Unknown Fabric resources stay out of empty mention results")
    func hidesGenericFabricResourcesWithoutQuery() async throws {
        let viewModel = MentionSuggestionsViewModel()
        viewModel.fabricClient = FabricMentionClientStub(
            resources: [
                FabricResourceDescriptor(
                    uri: FabricURI(appID: "external.docs", kind: "document", id: "roadmap"),
                    kind: "document",
                    title: "Platform Roadmap",
                    summary: "Q3 planning document",
                    capabilities: [.read, .mention]
                )
            ]
        )

        viewModel.updateSuggestions(for: "", excluding: [], currentTabId: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(
            !viewModel.suggestions.contains {
                if case .fabricResource = $0.mention {
                    return true
                }
                return false
            }
        )
    }

    @Test("Fabric page snapshots appear as a distinct mention option")
    func suggestsFabricPageSnapshots() async throws {
        let tabID = UUID()
        let viewModel = MentionSuggestionsViewModel()
        viewModel.fabricClient = FabricMentionClientStub(
            resources: [
                FabricResourceDescriptor(
                    uri: FabricURI(appID: WheelFabricAppID.browser, kind: "page-snapshot", id: tabID.uuidString),
                    kind: "page-snapshot",
                    title: "Page Snapshot",
                    summary: "Checkout flow",
                    capabilities: [.read, .mention],
                    metadata: [
                        "url": .string("https://example.com/checkout")
                    ]
                )
            ]
        )

        viewModel.updateSuggestions(for: "snapshot", excluding: [], currentTabId: tabID)

        for _ in 0..<20 {
            if viewModel.suggestions.contains(where: {
                if case .pageSnapshot(let id, let title, let url) = $0.mention {
                    return id == tabID
                        && title == "Checkout flow"
                        && url == "https://example.com/checkout"
                }
                return false
            }) {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(
            viewModel.suggestions.contains {
                if case .pageSnapshot(let id, let title, let url) = $0.mention {
                    return id == tabID
                        && title == "Checkout flow"
                        && url == "https://example.com/checkout"
                }
                return false
            }
        )
    }

    @Test("Fabric note resources appear in chat mention suggestions")
    func suggestsFabricNotes() async throws {
        let noteID = UUID()
        let viewModel = MentionSuggestionsViewModel()
        viewModel.fabricClient = FabricMentionClientStub(
            resources: [
                FabricResourceDescriptor(
                    uri: FabricURI(appID: WheelFabricAppID.notes, kind: "note", id: noteID.uuidString),
                    kind: "note",
                    title: "Quarterly roadmap",
                    summary: "Mention notes directly from chat.",
                    capabilities: [.read, .mention]
                )
            ]
        )

        viewModel.updateSuggestions(for: "roadmap", excluding: [], currentTabId: nil)

        for _ in 0..<20 {
            if viewModel.suggestions.contains(where: {
                if case .note(let id, _, _) = $0.mention {
                    return id == noteID
                }
                return false
            }) {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(
            viewModel.suggestions.contains {
                if case .note(let id, _, _) = $0.mention {
                    return id == noteID
                }
                return false
            }
        )
    }

    @Test("Notes appear in chat mention suggestions")
    func suggestsNotes() async throws {
        OverlayWindowManager.shared.closeAll()

        let store = NoteStore(
            storageRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            saveDebounceInterval: .seconds(60)
        )
        store.bindToWorkspace(UUID())

        let note = store.createNote()
        store.updateDocument(
            id: note.id,
            document: NoteDocument(
                root: [
                    "type": AnyCodable("doc"),
                    "content": AnyCodable([
                        [
                            "type": "paragraph",
                            "content": [
                                [
                                    "type": "text",
                                    "text": "Quarterly roadmap",
                                ],
                            ],
                        ],
                        [
                            "type": "paragraph",
                            "content": [
                                [
                                    "type": "text",
                                    "text": "Mention notes directly from chat.",
                                ],
                            ],
                        ],
                    ]),
                ]
            )
        )

        let viewModel = MentionSuggestionsViewModel()
        viewModel.noteStore = store
        viewModel.updateSuggestions(for: "roadmap", excluding: [], currentTabId: nil)

        for _ in 0..<20 {
            if viewModel.suggestions.contains(where: {
                if case .note(let id, _, _) = $0.mention {
                    return id == note.id
                }
                return false
            }) {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(
            viewModel.suggestions.contains {
                if case .note(let id, _, _) = $0.mention {
                    return id == note.id
                }
                return false
            }
        )
    }
}
