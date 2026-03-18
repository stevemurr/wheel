import Foundation

enum BrowserExperience {
    static let agentAutomationEnabled = false

    static func showsOmniBarModule(_ moduleID: OmniBarModuleID) -> Bool {
        switch moduleID {
        case .agent:
            agentAutomationEnabled
        default:
            true
        }
    }
}
