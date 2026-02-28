import Foundation

extension URLResponse {
    /// Cast to HTTPURLResponse and validate the status code
    /// - Parameter acceptableRange: Range of acceptable HTTP status codes (default: 200...299)
    /// - Returns: The validated HTTPURLResponse
    /// - Throws: URLError(.badServerResponse) if the response is not HTTP or the status code is outside the acceptable range
    func asValidHTTPResponse(acceptableRange: ClosedRange<Int> = 200...299) throws -> HTTPURLResponse {
        guard let http = self as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard acceptableRange.contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return http
    }
}
