import Foundation

enum WidgetManifestValidationError: LocalizedError, Equatable {
    case invalidVersion(String)
    case invalidTTL(Int)
    case emptySkillChain
    case invalidStepSequence(expected: Int, actual: Int)
    case duplicateOutputKey(String)
    case invalidReturns(String)
    case invalidConfig(String)
    case invalidFetchURL(String, String)
    case missingSkillParameter(WidgetSkillName, String)
    case invalidSkillParameter(WidgetSkillName, String)
    case unresolvedReference(step: Int, reference: String)

    var errorDescription: String? {
        switch self {
        case .invalidVersion(let version):
            return "Unsupported widget manifest version '\(version)'."
        case .invalidTTL(let ttl):
            return "Widget TTL must be zero or greater. Got \(ttl)."
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
        case .missingSkillParameter(let skill, let parameter):
            return "Widget skill '\(skill.rawValue)' is missing required parameter '\(parameter)'."
        case .invalidSkillParameter(let skill, let parameter):
            return "Widget skill '\(skill.rawValue)' has an invalid '\(parameter)' parameter."
        case .unresolvedReference(let step, let reference):
            return "Widget step \(step) references '\(reference)' before it exists."
        }
    }
}

enum WidgetManifestValidator {
    static func validate(_ manifest: WidgetManifest) throws -> WidgetManifest {
        let manifest = WidgetManifestRepair.repair(manifest).manifest

        guard manifest.version == "1" else {
            throw WidgetManifestValidationError.invalidVersion(manifest.version)
        }

        guard manifest.ttl >= 0 else {
            throw WidgetManifestValidationError.invalidTTL(manifest.ttl)
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

            try validateParameters(for: step, availableOutputKeys: outputKeys.subtracting(Set([step.outputKey])))

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

    private static func validateParameters(
        for step: WidgetSkillStep,
        availableOutputKeys: Set<String>
    ) throws {
        switch step.skill {
        case .currentDateTime:
            if let timeZone = step.params["timeZone"], !isNonEmptyString(timeZone) {
                throw WidgetManifestValidationError.invalidSkillParameter(step.skill, "timeZone")
            }
        case .fetchUrl:
            guard let url = step.params["url"], isNonEmptyString(url) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "url")
            }
            let method = step.params["method"]?.stringValue?.uppercased() ?? "GET"
            if let method = step.params["method"]?.stringValue {
                let normalized = method.uppercased()
                guard normalized == "GET" || normalized == "POST" else {
                    throw WidgetManifestValidationError.invalidSkillParameter(step.skill, "method")
                }
            }
            if let headers = step.params["headers"] {
                guard let dictionary = headers.dictionaryValue,
                      dictionary.values.allSatisfy({ $0 is String }) else {
                    throw WidgetManifestValidationError.invalidSkillParameter(step.skill, "headers")
                }
            }
            if let body = step.params["body"],
               !(body.value is String),
               body.dictionaryValue == nil,
               body.arrayValue == nil,
               !body.isNull {
                throw WidgetManifestValidationError.invalidSkillParameter(step.skill, "body")
            }
            if step.params["body"] != nil, method != "POST" {
                throw WidgetManifestValidationError.invalidSkillParameter(step.skill, "body")
            }
        case .parseHtml:
            guard let html = step.params["html"], isSupportedStructuredValue(html) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "html")
            }
            guard let selector = step.params["selector"], isNonEmptyString(selector) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "selector")
            }
        case .parseJson:
            guard let json = step.params["json"], isSupportedStructuredValue(json) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "json")
            }
        case .extractWithRegex:
            guard let text = step.params["text"], isSupportedStructuredValue(text) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "text")
            }
            guard let pattern = step.params["pattern"], isNonEmptyString(pattern) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "pattern")
            }
        case .parseCsv:
            guard let csv = step.params["csv"], isSupportedStructuredValue(csv) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "csv")
            }
        case .transform:
            guard let data = step.params["data"], isSupportedStructuredValue(data) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "data")
            }
            guard let mapping = step.params["mapping"]?.dictionaryValue, !mapping.isEmpty else {
                throw WidgetManifestValidationError.invalidSkillParameter(step.skill, "mapping")
            }
        case .filterSort:
            guard let data = step.params["data"], isSupportedStructuredValue(data) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "data")
            }
        case .mergeArrays:
            guard let arrays = step.params["arrays"]?.arrayValue, !arrays.isEmpty else {
                throw WidgetManifestValidationError.invalidSkillParameter(step.skill, "arrays")
            }
        case .computeStats:
            guard let data = step.params["data"], isSupportedStructuredValue(data) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "data")
            }
            guard let field = step.params["field"], isNonEmptyString(field) else {
                throw WidgetManifestValidationError.missingSkillParameter(step.skill, "field")
            }
            guard let ops = step.params["ops"]?.arrayValue,
                  !ops.isEmpty,
                  ops.allSatisfy({ $0 is String }) else {
                throw WidgetManifestValidationError.invalidSkillParameter(step.skill, "ops")
            }
        }

        for value in step.params.values {
            try validateReferences(in: value.value, availableOutputKeys: availableOutputKeys, stepNumber: step.step)
        }
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
            if let linkField = config.linkField, linkField.isEmpty {
                throw WidgetManifestValidationError.invalidConfig("list linkField must not be empty when provided.")
            }
        case .text:
            break
        case .priceCard(let config):
            guard !config.title.isEmpty, !config.priceField.isEmpty else {
                throw WidgetManifestValidationError.invalidConfig("priceCard config requires title and priceField.")
            }
        }
    }

    private static func validateReferences(
        in value: Any,
        availableOutputKeys: Set<String>,
        stepNumber: Int
    ) throws {
        switch value {
        case let string as String:
            guard string.hasPrefix("$") else { return }
            let body = String(string.dropFirst())
            let root = body.split(separator: ".", omittingEmptySubsequences: true).first.map(String.init) ?? body
            guard availableOutputKeys.contains(root) else {
                throw WidgetManifestValidationError.unresolvedReference(step: stepNumber, reference: string)
            }
        case let array as [Any]:
            for item in array {
                try validateReferences(in: item, availableOutputKeys: availableOutputKeys, stepNumber: stepNumber)
            }
        case let dictionary as [String: Any]:
            for nested in dictionary.values {
                try validateReferences(in: nested, availableOutputKeys: availableOutputKeys, stepNumber: stepNumber)
            }
        default:
            return
        }
    }

    private static func isNonEmptyString(_ value: AnyCodable) -> Bool {
        guard let string = value.stringValue else { return false }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private static func isSupportedStructuredValue(_ value: AnyCodable) -> Bool {
        isNonEmptyString(value) || value.dictionaryValue != nil || value.arrayValue != nil
    }
}
