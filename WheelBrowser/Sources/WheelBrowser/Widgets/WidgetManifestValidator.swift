import Foundation

enum WidgetManifestValidationError: LocalizedError, Equatable {
    case invalidVersion(String)
    case emptySkillChain
    case invalidStepSequence(expected: Int, actual: Int)
    case duplicateOutputKey(String)
    case invalidReturns(String)
    case invalidConfig(String)
    case invalidFetchURL(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidVersion(let version):
            return "Unsupported widget manifest version '\(version)'."
        case .emptySkillChain:
            return "Widget manifests must include at least one skill step."
        case .invalidStepSequence(let expected, let actual):
            return "Widget skill steps must be sequential starting at 1. Expected \(expected), got \(actual)."
        case .duplicateOutputKey(let key):
            return "Widget skill steps must use unique output keys. Duplicate key '\(key)'."
        case .invalidReturns(let key):
            return "Widget returns '\(key)' does not match any skill output."
        case .invalidConfig(let message):
            return message
        case .invalidFetchURL(_, let message):
            return message
        }
    }
}

enum WidgetManifestValidator {
    static func validate(_ manifest: WidgetManifest) throws -> WidgetManifest {
        guard manifest.version == "1" else {
            throw WidgetManifestValidationError.invalidVersion(manifest.version)
        }

        guard !manifest.skillChain.isEmpty else {
            throw WidgetManifestValidationError.emptySkillChain
        }

        var expectedStep = 1
        var outputKeys = Set<String>()
        for step in manifest.skillChain {
            guard step.step == expectedStep else {
                throw WidgetManifestValidationError.invalidStepSequence(
                    expected: expectedStep,
                    actual: step.step
                )
            }

            if !outputKeys.insert(step.outputKey).inserted {
                throw WidgetManifestValidationError.duplicateOutputKey(step.outputKey)
            }

            if step.skill == .fetchUrl {
                guard let rawURL = step.params["url"]?.stringValue,
                      let url = URL(string: rawURL) else {
                    throw WidgetManifestValidationError.invalidFetchURL(
                        step.params["url"]?.stringValue ?? "",
                        "Each fetchUrl step must declare a static HTTPS URL."
                    )
                }
                if rawURL.hasPrefix("$") {
                    throw WidgetManifestValidationError.invalidFetchURL(
                        rawURL,
                        "fetchUrl URLs must be static so the allowlist can be derived up front."
                    )
                }
                try WidgetNetworkPolicy.validateRemoteURL(url)
            }

            expectedStep += 1
        }

        guard outputKeys.contains(manifest.returns) else {
            throw WidgetManifestValidationError.invalidReturns(manifest.returns)
        }

        try validateConfig(manifest.config)
        return manifest
    }

    private static func validateConfig(_ config: WidgetConfig) throws {
        switch config {
        case .barChart(let config):
            guard !config.title.isEmpty, !config.xField.isEmpty, !config.yField.isEmpty else {
                throw WidgetManifestValidationError.invalidConfig("barChart config requires title, xField, and yField.")
            }
        case .lineChart(let config):
            guard !config.title.isEmpty, !config.xField.isEmpty, !config.series.isEmpty else {
                throw WidgetManifestValidationError.invalidConfig("lineChart config requires title, xField, and at least one series.")
            }
        case .statCard(let config):
            guard !config.title.isEmpty, !config.valueField.isEmpty else {
                throw WidgetManifestValidationError.invalidConfig("statCard config requires title and valueField.")
            }
        case .table(let config):
            guard !config.title.isEmpty, !config.columns.isEmpty else {
                throw WidgetManifestValidationError.invalidConfig("table config requires title and at least one column.")
            }
        case .list(let config):
            guard !config.title.isEmpty, !config.labelField.isEmpty else {
                throw WidgetManifestValidationError.invalidConfig("list config requires title and labelField.")
            }
        case .text:
            break
        case .priceCard(let config):
            guard !config.title.isEmpty, !config.priceField.isEmpty else {
                throw WidgetManifestValidationError.invalidConfig("priceCard config requires title and priceField.")
            }
        }
    }
}
