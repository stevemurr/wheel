import Foundation
import WebKit

/// Handles the compilation of content blocking rules into WKContentRuleList objects.
/// Takes merged rule dictionaries and produces compiled WebKit rule lists.
@MainActor
final class RuleCompilationPipeline {

    /// Maximum number of rules WebKit can handle
    static var maxRuleCount: Int { WebKitRuleConverter.maxRulesPerList }

    /// Compiles an array of rule dictionaries into a WKContentRuleList.
    /// - Parameter rules: The array of rule dictionaries in WebKit content blocker JSON format.
    /// - Returns: A compiled `WKContentRuleList`.
    /// - Throws: `ContentBlockerError.compilationFailed` if serialization or compilation fails.
    func compile(_ rules: [[String: Any]]) async throws -> WKContentRuleList {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let rulesJSON = String(data: jsonData, encoding: .utf8) else {
            throw ContentBlockerError.compilationFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: BlockingRules.ruleSetIdentifier,
                encodedContentRuleList: rulesJSON
            ) { ruleList, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let ruleList = ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: ContentBlockerError.compilationFailed)
                }
            }
        }
    }

    /// Compiles rules with fallback: tries the full set first, then falls back to built-in only.
    /// - Parameters:
    ///   - builtInRules: The built-in rules that are always expected to compile successfully.
    ///   - externalRules: External filter list rules that may cause compilation failures.
    /// - Returns: A compiled `WKContentRuleList`.
    /// - Throws: `ContentBlockerError.compilationFailed` if even built-in rules fail to compile.
    func compileWithFallback(
        builtInRules: [[String: Any]],
        externalRules: [[String: Any]]
    ) async throws -> WKContentRuleList {
        // If no external rules, compile built-in only
        guard !externalRules.isEmpty else {
            return try await compile(builtInRules)
        }

        // Merge and truncate if needed
        var allRules = builtInRules
        allRules.append(contentsOf: externalRules)

        if allRules.count > Self.maxRuleCount {
            Log.AdBlock.info("Truncating rules from \(allRules.count) to \(Self.maxRuleCount)")
            allRules = Array(allRules.prefix(Self.maxRuleCount))
        }

        // Try to compile with all rules
        if let result = try? await compile(allRules) {
            Log.AdBlock.info("Compiled \(allRules.count) rules (including external)")
            return result
        }

        // If that failed, fall back to built-in rules only
        Log.AdBlock.warning("External rules caused compilation failure, falling back to built-in only")
        return try await compile(builtInRules)
    }
}
