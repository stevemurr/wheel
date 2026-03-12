import Foundation
import Testing
@testable import WheelBrowser
import Fabric

@Suite("ConversationHistoryBuilder")
struct ConversationHistoryBuilderTests {
    @Test("Previously injected website context is not prepended again")
    func skipsRepeatedWebsiteContext() {
        let context = PageContext(
            url: "https://example.com/docs",
            title: "Docs",
            textContent: "First page snapshot"
        )

        let existingKeys = Set(ConversationHistoryBuilder.injectedContextKeys(for: [context]))
        let filtered = ConversationHistoryBuilder.pageContextsRequiringInjection(
            [context],
            previouslyInjectedContextKeys: existingKeys
        )

        #expect(filtered.isEmpty)
        #expect(ConversationHistoryBuilder.buildFullMessage(content: "What changed?", pageContexts: filtered) == "What changed?")
    }

    @Test("Website context is reinjected when the page content changes")
    func reinjectsChangedWebsiteContext() {
        let original = PageContext(
            url: "https://example.com/docs",
            title: "Docs",
            textContent: "First page snapshot"
        )
        let updated = PageContext(
            url: "https://example.com/docs",
            title: "Docs",
            textContent: "Updated page snapshot"
        )

        let existingKeys = Set(ConversationHistoryBuilder.injectedContextKeys(for: [original]))
        let filtered = ConversationHistoryBuilder.pageContextsRequiringInjection(
            [updated],
            previouslyInjectedContextKeys: existingKeys
        )

        #expect(filtered.count == 1)
        #expect(filtered.first?.textContent == "Updated page snapshot")
    }

    @Test("Previously injected Fabric resource context is not prepended again")
    func skipsRepeatedFabricResourceContext() {
        let uri = FabricURI(appID: "external.docs", kind: "document", id: "roadmap")
        let context = PageContext(
            url: uri.rawValue,
            title: "Platform Roadmap",
            textContent: "Q3 planning document",
            contextBadge: .fabricResource(uri: uri, title: "Platform Roadmap")
        )

        let existingKeys = Set(ConversationHistoryBuilder.injectedContextKeys(for: [context]))
        let filtered = ConversationHistoryBuilder.pageContextsRequiringInjection(
            [context],
            previouslyInjectedContextKeys: existingKeys
        )

        #expect(filtered.isEmpty)
    }
}
