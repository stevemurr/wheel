import Foundation

@MainActor
protocol OmniBarCommandHandling: AnyObject {
    func handle(_ command: OmniBarExternalCommand)
}

enum OmniBarExternalCommand: Equatable {
    case focusAddressBar(selectAll: Bool = true)
    case focusChatInput(prefill: String? = nil)
    case focusAISidebar
    case focusSemanticSearch
    case focusReadingList
    case escape
    case findInPage
    case toggleSavePage
    case copyLastResponse
    case regenerateResponse
    case editLastMessage
}

@MainActor
final class OmniBarCommandCenter {
    static let shared = OmniBarCommandCenter()

    weak var handler: (any OmniBarCommandHandling)?

    func register(_ handler: any OmniBarCommandHandling) {
        self.handler = handler
    }

    func unregister(_ handler: any OmniBarCommandHandling) {
        guard self.handler === handler else { return }
        self.handler = nil
    }

    func send(_ command: OmniBarExternalCommand) {
        handler?.handle(command)
    }
}
