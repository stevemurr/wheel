import Foundation
import Testing
@testable import WheelBrowser

@Suite("WheelModelContextService")
struct WheelModelContextServiceTests {
    @Test("Thread IDs are namespaced by surface")
    func threadIDRouting() {
        let conversationID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let tabID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let runID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
        let requestID = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!

        #expect(
            WheelModelContextService.chatThreadID(for: conversationID)
                == "chat:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )
        #expect(
            WheelModelContextService.agentThreadID(tabId: tabID, runId: runID)
                == "agent:11111111-2222-3333-4444-555555555555:66666666-7777-8888-9999-aaaaaaaaaaaa"
        )
        #expect(
            WheelModelContextService.summaryThreadID(for: requestID)
                == "summary:bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
        )
        #expect(
            WheelModelContextService.widgetThreadID(for: requestID)
                == "widget:bbbbbbbb-cccc-dddd-eeee-ffffffffffff"
        )
    }
}
