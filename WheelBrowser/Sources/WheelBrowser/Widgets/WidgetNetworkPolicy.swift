import Foundation

enum WidgetNetworkPolicy {
    static func validateRemoteURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else {
            throw WidgetManifestValidationError.invalidFetchURL(
                url.absoluteString,
                "Widget fetches must use HTTPS."
            )
        }

        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw WidgetManifestValidationError.invalidFetchURL(
                url.absoluteString,
                "Widget fetches must target a valid host."
            )
        }

        if isBlockedHost(host) {
            throw WidgetManifestValidationError.invalidFetchURL(
                url.absoluteString,
                "Widget fetches cannot target local or private-network hosts."
            )
        }
    }

    static func isBlockedHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        if lowered == "localhost" || lowered.hasSuffix(".local") {
            return true
        }

        if lowered == "0.0.0.0" || lowered == "::1" {
            return true
        }

        let octets = lowered.split(separator: ".")
        if octets.count == 4, let first = Int(octets[0]), let second = Int(octets[1]) {
            if first == 10 || first == 127 {
                return true
            }
            if first == 169 && second == 254 {
                return true
            }
            if first == 192 && second == 168 {
                return true
            }
            if first == 172 && (16...31).contains(second) {
                return true
            }
        }

        let ipv6Prefixes = ["fc", "fd", "fe80"]
        return ipv6Prefixes.contains { lowered.hasPrefix($0) }
    }
}
