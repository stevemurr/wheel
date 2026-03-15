import Foundation

enum BrowserExperience {
    static let aiChatEnabled = false
    static let agentAutomationEnabled = false

    static func showsOmniBarModule(_ moduleID: OmniBarModuleID) -> Bool {
        switch moduleID {
        case .chat:
            aiChatEnabled
        case .agent:
            agentAutomationEnabled
        default:
            true
        }
    }
}
