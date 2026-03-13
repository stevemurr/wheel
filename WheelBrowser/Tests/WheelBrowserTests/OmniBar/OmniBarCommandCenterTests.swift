import Testing
@testable import WheelBrowser

@MainActor
@Suite("OmniBar Command Center")
struct OmniBarCommandCenterTests {
    private final class Handler: OmniBarCommandHandling {
        var commands: [OmniBarExternalCommand] = []

        func handle(_ command: OmniBarExternalCommand) {
            commands.append(command)
        }
    }

    @Test("Command center forwards typed commands to the registered handler")
    func forwardsCommands() {
        let commandCenter = OmniBarCommandCenter()
        let handler = Handler()
        commandCenter.register(handler)

        commandCenter.send(.focusChatInput(prefill: "summarize this"))
        commandCenter.send(.toggleSavePage)

        #expect(handler.commands == [
            .focusChatInput(prefill: "summarize this"),
            .toggleSavePage,
        ])
    }

    @Test("Unregister clears the active handler")
    func unregisterClearsHandler() {
        let commandCenter = OmniBarCommandCenter()
        let handler = Handler()
        commandCenter.register(handler)
        commandCenter.unregister(handler)

        commandCenter.send(.focusSemanticSearch)

        #expect(handler.commands.isEmpty)
    }
}
