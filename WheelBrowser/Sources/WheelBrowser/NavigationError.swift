import Foundation

enum NavigationError: Equatable {
    case network(message: String)
    case ssl(message: String)
    case timeout
    case hostNotFound
    case resourceNotFound
    case serverError
    case unknown(message: String)

    static func == (lhs: NavigationError, rhs: NavigationError) -> Bool {
        switch (lhs, rhs) {
        case (.network(let a), .network(let b)): return a == b
        case (.ssl(let a), .ssl(let b)): return a == b
        case (.timeout, .timeout): return true
        case (.hostNotFound, .hostNotFound): return true
        case (.resourceNotFound, .resourceNotFound): return true
        case (.serverError, .serverError): return true
        case (.unknown(let a), .unknown(let b)): return a == b
        default: return false
        }
    }

    var isRetryable: Bool {
        switch self {
        case .network, .timeout, .hostNotFound, .serverError:
            return true
        case .ssl, .resourceNotFound, .unknown:
            return false
        }
    }

    var displayMessage: String {
        switch self {
        case .network(let message):
            return "Network Error\n\(message)"
        case .ssl(let message):
            return "SSL Error\n\(message)"
        case .timeout:
            return "The request timed out.\nThe server took too long to respond."
        case .hostNotFound:
            return "Server Not Found\nThe host could not be resolved."
        case .resourceNotFound:
            return "Page Not Found\nThe requested resource does not exist."
        case .serverError:
            return "Server Error\nThe server encountered an internal error."
        case .unknown(let message):
            return "Navigation Failed\n\(message)"
        }
    }
}
