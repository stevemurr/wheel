import Foundation

@MainActor
protocol OmniBarCommandHandling: AnyObject {
    func handle(_ command: OmniBarExternalCommand)
}

enum OmniBarExternalCommand: Equatable {
    case focusAddressBar(selectAll: Bool = true)
    case focusSemanticSearch
    case focusReadingList
    case escape
    case findInPage
    case toggleSavePage
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
