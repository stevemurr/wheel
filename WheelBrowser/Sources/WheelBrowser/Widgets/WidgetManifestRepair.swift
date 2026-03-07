import Foundation

enum WidgetManifestRepair {
    struct Result {
        let manifest: WidgetManifest
        let changed: Bool
    }

    static func repair(_ manifest: WidgetManifest) -> Result {
        guard isRedditChildListing(manifest) else {
            return Result(manifest: manifest, changed: false)
        }

        var repairedSteps: [WidgetSkillStep] = []
        repairedSteps.reserveCapacity(manifest.skillChain.count)

        var changed = false
        for step in manifest.skillChain {
            let repaired = repair(step)
            repairedSteps.append(repaired.step)
            changed = changed || repaired.changed
        }

        guard changed else {
            return Result(manifest: manifest, changed: false)
        }

        return Result(
            manifest: WidgetManifest(
                id: manifest.id,
                version: manifest.version,
                widgetType: manifest.widgetType,
                config: manifest.config,
                skillChain: repairedSteps,
                returns: manifest.returns,
                ttl: manifest.ttl,
                prompt: manifest.prompt
            ),
            changed: true
        )
    }

    private static func isRedditChildListing(_ manifest: WidgetManifest) -> Bool {
        let hasRedditFetch = manifest.skillChain.contains { step in
            guard step.skill == .fetchUrl,
                  let rawURL = step.params["url"]?.stringValue,
                  let url = URL(string: rawURL),
                  let host = url.host?.lowercased() else {
                return false
            }

            return host == "reddit.com" || host == "www.reddit.com"
        }

        let hasChildPath = manifest.skillChain.contains { step in
            guard step.skill == .parseJson,
                  let path = step.params["path"]?.stringValue else {
                return false
            }

            return normalizedJSONPath(path) == "data.children"
        }

        return hasRedditFetch && hasChildPath
    }

    private static func repair(_ step: WidgetSkillStep) -> (step: WidgetSkillStep, changed: Bool) {
        var params = step.params
        var changed = false

        switch step.skill {
        case .fetchUrl:
            if let rawURL = params["url"]?.stringValue,
               let repairedURL = repairRedditURL(rawURL),
               repairedURL != rawURL {
                params["url"] = AnyCodable(repairedURL)
                changed = true
            }
        case .filterSort:
            if let sortBy = params["sortBy"]?.stringValue {
                let repairedSortBy = repairRedditFieldPath(sortBy)
                if repairedSortBy != sortBy {
                    params["sortBy"] = AnyCodable(repairedSortBy)
                    changed = true
                }
            }

            if let filter = params["filter"]?.dictionaryValue {
                let repairedFilter = Dictionary(
                    uniqueKeysWithValues: filter.map { key, value in
                        (repairRedditFieldPath(key), value)
                    }
                )

                if NSDictionary(dictionary: repairedFilter).isEqual(to: filter) == false {
                    params["filter"] = AnyCodable(repairedFilter)
                    changed = true
                }
            }
        case .transform:
            if let mapping = params["mapping"]?.dictionaryValue {
                let repairedMapping = Dictionary(
                    uniqueKeysWithValues: mapping.map { key, value in
                        guard let path = value as? String else {
                            return (key, value)
                        }
                        return (key, repairRedditFieldPath(path))
                    }
                )

                if NSDictionary(dictionary: repairedMapping).isEqual(to: mapping) == false {
                    params["mapping"] = AnyCodable(repairedMapping)
                    changed = true
                }
            }
        default:
            break
        }

        guard changed else {
            return (step, false)
        }

        return (
            WidgetSkillStep(
                step: step.step,
                skill: step.skill,
                params: params,
                outputKey: step.outputKey
            ),
            true
        )
    }

    private static func repairRedditURL(_ rawURL: String) -> String? {
        guard var components = URLComponents(string: rawURL),
              let host = components.host?.lowercased(),
              host == "reddit.com" || host == "www.reddit.com" else {
            return nil
        }

        var queryItems = components.queryItems ?? []
        var didChange = false

        if components.path.lowercased().hasSuffix("/top.json"),
           queryItems.contains(where: { $0.name == "t" }) == false {
            queryItems.append(URLQueryItem(name: "t", value: "day"))
            didChange = true
        }

        if queryItems.contains(where: { $0.name == "raw_json" }) == false {
            queryItems.append(URLQueryItem(name: "raw_json", value: "1"))
            didChange = true
        }

        guard didChange else {
            return rawURL
        }

        components.queryItems = queryItems
        return components.url?.absoluteString ?? rawURL
    }

    private static func repairRedditFieldPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return path }
        guard trimmed.contains(".") == false, trimmed.contains("[") == false else { return path }
        guard trimmed.hasPrefix("expr:") == false,
              trimmed.hasPrefix("literal:") == false,
              trimmed.hasPrefix("$") == false else {
            return path
        }
        guard trimmed != "kind", trimmed != "data" else {
            return path
        }

        return "data.\(trimmed)"
    }

    private static func normalizedJSONPath(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$.", with: "")
    }
}
