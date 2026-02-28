import Foundation

/// Connection status for remote service connections (LLM, DIndex, etc.)
enum ConnectionStatus {
    case unknown, checking, connected, failed(String)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}
