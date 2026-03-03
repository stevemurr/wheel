import Foundation

/// Parameter validation errors for skills.
enum SkillParamError: LocalizedError {
    case missing(String)
    case invalid(String, String)

    var errorDescription: String? {
        switch self {
        case .missing(let param):
            return "Missing required parameter: \(param)"
        case .invalid(let param, let value):
            return "Invalid value for '\(param)': \(value)"
        }
    }
}

/// HTTP-level errors from acquisition skills.
enum SkillHTTPError: LocalizedError {
    case badStatus(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "HTTP request failed with status \(code)"
        case .parseError:
            return "Failed to parse response data"
        }
    }
}
