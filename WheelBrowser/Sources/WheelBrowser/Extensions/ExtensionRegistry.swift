import Foundation
import WebKit

@Observable
final class ExtensionRegistry {
    static let shared = ExtensionRegistry()

    private struct PersistedStateFile: Codable {
        var extensions: [InstalledExtensionState]
    }

    private struct RuntimeConfigurationSignature: Equatable {
        struct UserScriptSignature: Equatable {
            let id: String
            let source: String
            let injectionTime: WKUserScriptInjectionTime
            let forMainFrameOnly: Bool
        }

        let userScripts: [UserScriptSignature]
        let contentRuleListIdentifiers: [String]
    }

    private struct ExtensionCandidate {
        let manifest: ExtensionManifest?
        let rootURL: URL
        let source: ExtensionInstallSource
        var validationError: String?
    }

    private let fileManager: FileManager
    private let bundledExtensionsURL: URL?
    private let sideloadedExtensionsURL: URL
    private let contentBlockerManager: ContentBlockerManager
    private let stateStore: JSONBackedStore<PersistedStateFile>

    private var persistedStates: [String: InstalledExtensionState] = [:]
    private var runtimeSnapshot: ExtensionRuntimeSnapshot = .empty
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?

    private(set) var installedExtensions: [InstalledExtension] = []
    private(set) var isReloading: Bool = false
    private(set) var lastReloadError: String?
    private(set) var hasCompletedInitialRuntimeBootstrap: Bool = false

    init(
        bundledExtensionsURL: URL? = Bundle.module.resourceURL?.appendingPathComponent("Extensions", isDirectory: true),
        sideloadedExtensionsURL: URL = FileManager.extensionsDirectory,
        stateFileURL: URL = FileManager.appSupportDirectory.appendingPathComponent("extensions.json"),
        contentBlockerManager: ContentBlockerManager = .shared,
        fileManager: FileManager = .default
    ) {
        self.bundledExtensionsURL = bundledExtensionsURL
        self.sideloadedExtensionsURL = sideloadedExtensionsURL
        self.contentBlockerManager = contentBlockerManager
        self.fileManager = fileManager
        self.stateStore = JSONBackedStore(
            backend: FileSystemStoreBackend(rootURL: stateFileURL.deletingLastPathComponent()),
            key: StoreKey(stateFileURL.lastPathComponent),
            codingConfiguration: .prettyPrintedSortedKeys
        )
        loadPersistedStates()
    }

    func activeSnapshot() -> ExtensionRuntimeSnapshot {
        runtimeSnapshot
    }

    func extensionsDirectoryURL() -> URL {
        sideloadedExtensionsURL
    }

    @MainActor
    func bootstrapRuntimeIfNeeded() async {
        guard AppSettings.shared.extensionsEnabled else {
            runtimeSnapshot = .empty
            hasCompletedInitialRuntimeBootstrap = true
            return
        }

        if hasCompletedInitialRuntimeBootstrap {
            return
        }

        if let bootstrapTask {
            await bootstrapTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.reload(preferCachedResourcesOnly: true)
            self.hasCompletedInitialRuntimeBootstrap = true
            self.bootstrapTask = nil
        }
        bootstrapTask = task
        await task.value
    }

    @MainActor
    func setEnabled(_ enabled: Bool, for logicalID: String) async {
        var state = persistedStates[logicalID] ?? InstalledExtensionState(id: logicalID)
        state.isEnabled = enabled
        persistedStates[logicalID] = state
        savePersistedStates()
        await reload()
    }

    @MainActor
    func reload(preferCachedResourcesOnly: Bool = false) async {
        isReloading = true
        lastReloadError = nil
        defer { isReloading = false }

        let previousRuntimeSignature = runtimeConfigurationSignature(for: runtimeSnapshot)

        loadPersistedStates()

        let candidates = resolveDuplicateCandidates(discoverExtensions())
        installedExtensions = candidates.map(makeInstalledExtension(from:))
        contentBlockerManager.synchronize(with: installedExtensions)

        guard AppSettings.shared.extensionsEnabled else {
            clearRuntimeErrors()
            runtimeSnapshot = .empty
            if previousRuntimeSignature != runtimeConfigurationSignature(for: runtimeSnapshot) {
                postRuntimeDidUpdate()
            }
            return
        }

        let activeExtensions = installedExtensions.filter { $0.isValid && $0.isEnabled }
        let compiledRules = await contentBlockerManager.compileActiveRules(
            for: activeExtensions,
            preferCachedResourcesOnly: preferCachedResourcesOnly
        )
        applyRuntimeErrors(compiledRules.errorsByExtensionID)
        runtimeSnapshot = buildRuntimeSnapshot(
            for: activeExtensions,
            compiledRules: compiledRules
        )

        savePersistedStates()
        if previousRuntimeSignature != runtimeConfigurationSignature(for: runtimeSnapshot) {
            postRuntimeDidUpdate()
        }
    }

    private func discoverExtensions() -> [ExtensionCandidate] {
        let bundled = extensionDirectories(in: bundledExtensionsURL).map {
            loadCandidate(at: $0, source: .bundled)
        }
        let sideloaded = extensionDirectories(in: sideloadedExtensionsURL).map {
            loadCandidate(at: $0, source: .sideloaded)
        }
        return (bundled + sideloaded).sorted {
            if $0.source != $1.source {
                return $0.source.rawValue < $1.source.rawValue
            }
            return $0.rootURL.lastPathComponent < $1.rootURL.lastPathComponent
        }
    }

    private func extensionDirectories(in rootURL: URL?) -> [URL] {
        guard let rootURL else { return [] }
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let urls = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func loadCandidate(at rootURL: URL, source: ExtensionInstallSource) -> ExtensionCandidate {
        let manifestURL = rootURL.appendingPathComponent("extension.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return ExtensionCandidate(
                manifest: nil,
                rootURL: rootURL,
                source: source,
                validationError: "Missing extension.json"
            )
        }

        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data) else {
            return ExtensionCandidate(
                manifest: nil,
                rootURL: rootURL,
                source: source,
                validationError: "extension.json is not valid JSON"
            )
        }

        return ExtensionCandidate(
            manifest: manifest,
            rootURL: rootURL,
            source: source,
            validationError: validate(manifest: manifest, in: rootURL)
        )
    }

    private func resolveDuplicateCandidates(_ candidates: [ExtensionCandidate]) -> [ExtensionCandidate] {
        var grouped: [String: [ExtensionCandidate]] = [:]
        var resolved: [ExtensionCandidate] = []

        for candidate in candidates {
            guard let logicalID = candidate.manifest?.id else {
                resolved.append(candidate)
                continue
            }
            grouped[logicalID, default: []].append(candidate)
        }

        for (_, candidatesForID) in grouped {
            let sorted = candidatesForID.sorted { lhs, rhs in
                if lhs.source != rhs.source {
                    return lhs.source == .bundled && rhs.source == .sideloaded
                }
                return lhs.rootURL.lastPathComponent < rhs.rootURL.lastPathComponent
            }

            for (index, candidate) in sorted.enumerated() {
                if index == 0 {
                    resolved.append(candidate)
                } else {
                    var duplicate = candidate
                    duplicate.validationError = "Duplicate extension ID \(candidate.manifest?.id ?? ""). Bundled extensions take precedence."
                    resolved.append(duplicate)
                }
            }
        }

        return resolved.sorted {
            if $0.source != $1.source {
                return $0.source.rawValue < $1.source.rawValue
            }
            return $0.rootURL.lastPathComponent < $1.rootURL.lastPathComponent
        }
    }

    private func validate(manifest: ExtensionManifest, in rootURL: URL) -> String? {
        var errors: [String] = []

        if !isValidIdentifier(manifest.id) {
            errors.append("Invalid extension id \(manifest.id)")
        }

        if !manifest.contentBlockers.isEmpty && !manifest.capabilities.contains(.contentBlocking) {
            errors.append("Content blockers declared without contentBlocking capability")
        }

        if !manifest.contentScripts.isEmpty && !manifest.capabilities.contains(.contentScripts) {
            errors.append("Content scripts declared without contentScripts capability")
        }

        for blocker in manifest.contentBlockers {
            switch blocker.sourceType {
            case .local:
                guard let relativePath = blocker.path,
                      let assetURL = resolveAssetURL(path: relativePath, rootURL: rootURL),
                      fileManager.fileExists(atPath: assetURL.path) else {
                    errors.append("Missing local blocker asset for \(blocker.id)")
                    continue
                }
            case .remote:
                guard let urlString = blocker.url,
                      let url = URL(string: urlString),
                      url.scheme?.lowercased() == "https" else {
                    errors.append("Remote blocker \(blocker.id) must use an HTTPS URL")
                    continue
                }
            }
        }

        for script in manifest.contentScripts {
            if script.js.isEmpty && script.css.isEmpty {
                errors.append("Content script \(script.id) must declare at least one JS or CSS asset")
            }

            for asset in script.js + script.css {
                guard let assetURL = resolveAssetURL(path: asset, rootURL: rootURL),
                      fileManager.fileExists(atPath: assetURL.path) else {
                    errors.append("Missing content script asset \(asset) for \(script.id)")
                    continue
                }
            }
        }

        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    private func isValidIdentifier(_ identifier: String) -> Bool {
        let pattern = "^[A-Za-z0-9.-]+$"
        return identifier.range(of: pattern, options: .regularExpression) != nil
    }

    private func resolveAssetURL(path: String, rootURL: URL) -> URL? {
        let standardizedRoot = rootURL.standardizedFileURL
        let candidate = standardizedRoot.appendingPathComponent(path).standardizedFileURL
        let rootPath = standardizedRoot.path

        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    private func makeInstalledExtension(from candidate: ExtensionCandidate) -> InstalledExtension {
        let logicalID = candidate.manifest?.id
        let persistedState = logicalID.flatMap { persistedStates[$0] }
        let isEnabled = persistedState?.isEnabled ?? candidate.manifest?.defaultEnabled ?? false

        return InstalledExtension(
            id: "\(candidate.source.rawValue):\(candidate.rootURL.lastPathComponent)",
            logicalID: logicalID,
            manifest: candidate.manifest,
            rootURL: candidate.rootURL,
            source: candidate.source,
            isEnabled: isEnabled,
            lastValidationError: candidate.validationError,
            lastRuntimeError: persistedState?.lastRuntimeError
        )
    }

    private func buildRuntimeSnapshot(
        for extensions: [InstalledExtension],
        compiledRules: CompiledRuleSetBundle
    ) -> ExtensionRuntimeSnapshot {
        var userScripts: [ExtensionRuntimeUserScript] = []
        var ruleLists: [WKContentRuleList] = []
        var runtimeErrors: [String: String] = compiledRules.errorsByExtensionID

        for discovered in extensions {
            guard let manifest = discovered.manifest else { continue }

            if let compiledLists = compiledRules.ruleListsByExtensionID[manifest.id] {
                ruleLists.append(contentsOf: compiledLists)
            }

            if manifest.capabilities.contains(.contentScripts) {
                do {
                    userScripts.append(contentsOf: try makeRuntimeUserScripts(for: manifest, rootURL: discovered.rootURL))
                } catch {
                    let message = error.localizedDescription
                    if let existing = runtimeErrors[manifest.id] {
                        runtimeErrors[manifest.id] = existing + "\n" + message
                    } else {
                        runtimeErrors[manifest.id] = message
                    }
                }
            }
        }

        applyRuntimeErrors(runtimeErrors)

        return ExtensionRuntimeSnapshot(
            revision: UUID(),
            userScripts: userScripts,
            contentRuleLists: ruleLists
        )
    }

    private func makeRuntimeUserScripts(
        for manifest: ExtensionManifest,
        rootURL: URL
    ) throws -> [ExtensionRuntimeUserScript] {
        let allowlistedHosts = AppSettings.shared.adBlockDomainAllowlist
        return try manifest.contentScripts.map { script in
            let body = try loadScriptBody(spec: script, extensionID: manifest.id, rootURL: rootURL)
            let wrapped = wrapContentScript(
                id: "\(manifest.id).\(script.id)",
                body: body,
                matches: script.matches,
                excludeMatches: script.excludeMatches,
                allowlistedHosts: allowlistedHosts
            )

            return ExtensionRuntimeUserScript(
                id: "\(manifest.id).\(script.id)",
                source: wrapped,
                injectionTime: script.injectionTime.webKitValue,
                forMainFrameOnly: !script.allFrames
            )
        }
    }

    private func loadScriptBody(
        spec: ContentScriptSpec,
        extensionID: String,
        rootURL: URL
    ) throws -> String {
        var segments: [String] = []

        for relativePath in spec.js {
            guard let fileURL = resolveAssetURL(path: relativePath, rootURL: rootURL) else {
                throw ExtensionRegistryError.invalidAssetPath(relativePath)
            }
            segments.append(try String(contentsOf: fileURL, encoding: .utf8))
        }

        for (index, relativePath) in spec.css.enumerated() {
            guard let fileURL = resolveAssetURL(path: relativePath, rootURL: rootURL) else {
                throw ExtensionRegistryError.invalidAssetPath(relativePath)
            }
            let css = try String(contentsOf: fileURL, encoding: .utf8)
            let escapedCSS = JavaScriptEscaper.escape(css)
            let styleID = JavaScriptEscaper.escape("\(extensionID).\(spec.id).style.\(index)")
            segments.append(
                """
                (function() {
                    var styleId = '\(styleID)';
                    if (document.getElementById(styleId)) return;
                    var style = document.createElement('style');
                    style.id = styleId;
                    style.textContent = '\(escapedCSS)';
                    (document.head || document.documentElement).appendChild(style);
                })();
                """
            )
        }

        return segments.joined(separator: "\n")
    }

    private func wrapContentScript(
        id: String,
        body: String,
        matches: [String],
        excludeMatches: [String],
        allowlistedHosts: [String]
    ) -> String {
        let matchPatterns = jsonString(matches.map(globToRegexSource))
        let excludePatterns = jsonString(excludeMatches.map(globToRegexSource))
        let allowlistJSON = jsonString(allowlistedHosts)
        let escapedID = JavaScriptEscaper.escape(id)

        return """
        (function() {
            var scriptId = '\(escapedID)';
            window.__wheelExtensionScripts = window.__wheelExtensionScripts || {};
            if (window.__wheelExtensionScripts[scriptId]) return;

            var url = String(location.href || '');
            var host = String(location.hostname || '').toLowerCase();
            var allowlistedHosts = \(allowlistJSON);
            if (allowlistedHosts.some(function(entry) {
                return host === entry || host.endsWith('.' + entry);
            })) {
                return;
            }

            var matches = \(matchPatterns).map(function(pattern) { return new RegExp(pattern, 'i'); });
            var excludes = \(excludePatterns).map(function(pattern) { return new RegExp(pattern, 'i'); });
            if (matches.length && !matches.some(function(pattern) { return pattern.test(url); })) {
                return;
            }
            if (excludes.some(function(pattern) { return pattern.test(url); })) {
                return;
            }

            window.__wheelAllowlistedHosts = allowlistedHosts;
            window.__wheelExtensionScripts[scriptId] = true;
            \(body)
        })();
        """
    }

    private func jsonString(_ values: [String]) -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func globToRegexSource(_ pattern: String) -> String {
        var escaped = ""
        for character in pattern {
            switch character {
            case "*":
                escaped += ".*"
            case "?", ".":
                escaped += "."
            default:
                let scalar = String(character)
                if "\\.+()[]{}|^$".contains(character) {
                    escaped += "\\\(scalar)"
                } else {
                    escaped += scalar
                }
            }
        }
        return "^\(escaped)$"
    }

    private func clearRuntimeErrors() {
        for index in installedExtensions.indices {
            installedExtensions[index].lastRuntimeError = nil
            if let logicalID = installedExtensions[index].logicalID {
                var state = persistedStates[logicalID] ?? InstalledExtensionState(id: logicalID)
                state.lastRuntimeError = nil
                persistedStates[logicalID] = state
            }
        }
        savePersistedStates()
    }

    private func applyRuntimeErrors(_ runtimeErrors: [String: String]) {
        for index in installedExtensions.indices {
            guard let logicalID = installedExtensions[index].logicalID else { continue }
            let error = runtimeErrors[logicalID]
            installedExtensions[index].lastRuntimeError = error

            var state = persistedStates[logicalID] ?? InstalledExtensionState(id: logicalID)
            state.isEnabled = installedExtensions[index].isEnabled
            state.lastValidationError = installedExtensions[index].lastValidationError
            state.lastRuntimeError = error
            persistedStates[logicalID] = state
        }
    }

    private func postRuntimeDidUpdate() {
        NotificationCenter.default.post(name: .extensionRuntimeDidUpdate, object: self)
    }

    private func runtimeConfigurationSignature(
        for snapshot: ExtensionRuntimeSnapshot
    ) -> RuntimeConfigurationSignature {
        RuntimeConfigurationSignature(
            userScripts: snapshot.userScripts.map {
                RuntimeConfigurationSignature.UserScriptSignature(
                    id: $0.id,
                    source: $0.source,
                    injectionTime: $0.injectionTime,
                    forMainFrameOnly: $0.forMainFrameOnly
                )
            },
            contentRuleListIdentifiers: snapshot.contentRuleLists.map(\.identifier)
        )
    }

    private func loadPersistedStates() {
        guard let decoded = try? stateStore.load() else {
            persistedStates = [:]
            return
        }

        persistedStates = Dictionary(uniqueKeysWithValues: decoded.extensions.map { ($0.id, $0) })
    }

    private func savePersistedStates() {
        let state = PersistedStateFile(
            extensions: persistedStates.values.sorted { $0.id < $1.id }
        )
        try? stateStore.save(state)
    }
}

enum ExtensionRegistryError: LocalizedError {
    case invalidAssetPath(String)

    var errorDescription: String? {
        switch self {
        case .invalidAssetPath(let path):
            return "Invalid extension asset path \(path)."
        }
    }
}

extension Notification.Name {
    static let extensionRuntimeDidUpdate = Notification.Name("extensionRuntimeDidUpdate")
}
