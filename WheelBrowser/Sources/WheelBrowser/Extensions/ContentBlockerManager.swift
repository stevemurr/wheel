import CryptoKit
import Foundation
import WebKit

struct CompiledRuleSetBundle {
    let ruleListsByExtensionID: [String: [WKContentRuleList]]
    let errorsByExtensionID: [String: String]
}

@Observable
final class ContentBlockerManager: @unchecked Sendable {
    static let shared = ContentBlockerManager()

    private struct PersistedState: Codable {
        var subscriptions: [FilterListSubscriptionState]
    }

    private struct RemoteSourceContext {
        let extensionID: String
        let spec: ContentBlockerSpec
    }

    private struct LocalSourceContext {
        let extensionID: String
        let spec: ContentBlockerSpec
        let rootURL: URL
    }

    private let session: URLSession
    private let cacheDirectoryURL: URL
    private let ruleListStore: WKContentRuleListStore
    private let stateStore: JSONBackedStore<PersistedState>
    private var refreshTimer: Timer?
    private var knownRemoteSources: [String: RemoteSourceContext] = [:]
    private var knownLocalSources: [String: LocalSourceContext] = [:]

    private(set) var subscriptions: [FilterListSubscriptionState] = []
    private(set) var lastRefreshAt: Date?
    private(set) var lastRefreshError: String?

    init(
        session: URLSession = .shared,
        stateFileURL: URL = FileManager.appSupportDirectory.appendingPathComponent("filter_lists.json"),
        cacheDirectoryURL: URL = FileManager.contentBlockerCacheDirectory,
        ruleListStore: WKContentRuleListStore = .default()
    ) {
        self.session = session
        self.cacheDirectoryURL = cacheDirectoryURL
        self.ruleListStore = ruleListStore
        self.stateStore = JSONBackedStore(
            backend: FileSystemStoreBackend(rootURL: stateFileURL.deletingLastPathComponent()),
            key: StoreKey(stateFileURL.lastPathComponent),
            codingConfiguration: .prettyPrintedSortedKeysISO8601
        )
        try? FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: stateFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        loadState()
    }

    func subscriptions(for extensionID: String) -> [FilterListSubscriptionState] {
        subscriptions
            .filter { $0.extensionID == extensionID }
            .sorted { lhs, rhs in
                if lhs.isCustom != rhs.isCustom {
                    return !lhs.isCustom && rhs.isCustom
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    @MainActor
    func synchronize(with extensions: [InstalledExtension]) {
        var remoteSources: [String: RemoteSourceContext] = [:]
        var localSources: [String: LocalSourceContext] = [:]
        let activeExtensionIDs = Set(extensions.compactMap(\.logicalID))

        for discovered in extensions {
            guard let manifest = discovered.manifest else { continue }
            for spec in manifest.contentBlockers {
                switch spec.sourceType {
                case .remote:
                    let subscriptionID = builtInSubscriptionID(extensionID: manifest.id, specID: spec.id)
                    remoteSources[subscriptionID] = RemoteSourceContext(extensionID: manifest.id, spec: spec)
                case .local:
                    let sourceID = blockerSourceID(extensionID: manifest.id, sourceID: spec.id)
                    localSources[sourceID] = LocalSourceContext(
                        extensionID: manifest.id,
                        spec: spec,
                        rootURL: discovered.rootURL
                    )
                }
            }
        }

        knownRemoteSources = remoteSources
        knownLocalSources = localSources

        var merged: [FilterListSubscriptionState] = subscriptions
            .filter { $0.isCustom ? activeExtensionIDs.contains($0.extensionID) : false }

        for (subscriptionID, context) in remoteSources.sorted(by: { $0.key < $1.key }) {
            if let index = merged.firstIndex(where: { $0.id == subscriptionID }) {
                merged[index].name = context.spec.name
                merged[index].sourceURL = context.spec.url ?? merged[index].sourceURL
                merged[index].isCustom = false
                merged[index].isEnabled = effectiveEnabled(for: context.spec, existing: merged[index])
            } else {
                merged.append(
                    FilterListSubscriptionState(
                        id: subscriptionID,
                        extensionID: context.extensionID,
                        name: context.spec.name,
                        sourceURL: context.spec.url ?? "",
                        isCustom: false,
                        isEnabled: effectiveEnabled(for: context.spec, existing: nil),
                        etag: nil,
                        lastModified: nil,
                        checksum: nil,
                        lastCompiledChecksum: nil,
                        lastCompiledIdentifier: nil,
                        lastSuccessAt: nil,
                        lastError: nil
                    )
                )
            }
        }

        subscriptions = merged
            .filter { $0.isCustom || remoteSources[$0.id] != nil }
            .sorted { lhs, rhs in
                if lhs.extensionID != rhs.extensionID {
                    return lhs.extensionID < rhs.extensionID
                }
                if lhs.isCustom != rhs.isCustom {
                    return !lhs.isCustom && rhs.isCustom
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        saveState()
    }

    @MainActor
    func setSubscriptionEnabled(_ enabled: Bool, id: String) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index].isEnabled = enabled
        syncBuiltInToggleIfNeeded(for: subscriptions[index])
        saveState()
    }

    @MainActor
    func addCustomList(urlString: String, extensionID: String = "com.wheel.adblock") throws {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              let host = url.host else {
            throw ContentBlockerManagerError.invalidCustomListURL
        }

        if subscriptions.contains(where: { $0.sourceURL.caseInsensitiveCompare(urlString) == .orderedSame }) {
            throw ContentBlockerManagerError.duplicateCustomList
        }

        let id = "custom:\(UUID().uuidString.lowercased())"
        subscriptions.append(
            FilterListSubscriptionState(
                id: id,
                extensionID: extensionID,
                name: host,
                sourceURL: url.absoluteString,
                isCustom: true,
                isEnabled: true,
                etag: nil,
                lastModified: nil,
                checksum: nil,
                lastCompiledChecksum: nil,
                lastCompiledIdentifier: nil,
                lastSuccessAt: nil,
                lastError: nil
            )
        )
        saveState()
    }

    @MainActor
    func removeCustomList(id: String) {
        subscriptions.removeAll { $0.id == id && $0.isCustom }
        saveState()
    }

    @MainActor
    func refresh(force: Bool) async {
        lastRefreshError = nil
        for index in subscriptions.indices where subscriptions[index].isEnabled {
            do {
                try await refreshSubscription(at: index, force: force)
            } catch {
                subscriptions[index].lastError = error.localizedDescription
                lastRefreshError = error.localizedDescription
            }
        }
        lastRefreshAt = Date()
        saveState()
    }

    @MainActor
    func startAutomaticRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh(force: false)
                await ExtensionRegistry.shared.reload()
            }
        }
    }

    @MainActor
    func compileActiveRules(for extensions: [InstalledExtension]) async -> CompiledRuleSetBundle {
        var ruleListsByExtensionID: [String: [WKContentRuleList]] = [:]
        var errorsByExtensionID: [String: String] = [:]
        let allowlistedDomains = AppSettings.shared.adBlockDomainAllowlist

        for discovered in extensions {
            guard let manifest = discovered.manifest else { continue }
            var compiledLists: [WKContentRuleList] = []
            var errors: [String] = []

            for spec in manifest.contentBlockers where shouldCompile(spec, for: manifest.id) {
                let outcome: RuleListOutcome
                switch spec.sourceType {
                case .local:
                    outcome = await compileLocalRuleList(
                        extensionID: manifest.id,
                        spec: spec,
                        rootURL: discovered.rootURL,
                        allowlistedDomains: allowlistedDomains
                    )
                case .remote:
                    let subscriptionID = builtInSubscriptionID(extensionID: manifest.id, specID: spec.id)
                    outcome = await compileRemoteRuleList(
                        subscriptionID: subscriptionID,
                        allowlistedDomains: allowlistedDomains
                    )
                }

                if let ruleList = outcome.ruleList {
                    compiledLists.append(ruleList)
                }
                if let error = outcome.error {
                    errors.append(error)
                }
            }

            if manifest.id == "com.wheel.adblock" && AppSettings.shared.adBlockerEnabled {
                for subscription in subscriptions(for: manifest.id).filter(\.isCustom) where subscription.isEnabled {
                    let outcome = await compileRemoteRuleList(
                        subscriptionID: subscription.id,
                        allowlistedDomains: allowlistedDomains
                    )
                    if let ruleList = outcome.ruleList {
                        compiledLists.append(ruleList)
                    }
                    if let error = outcome.error {
                        errors.append(error)
                    }
                }
            }

            if !compiledLists.isEmpty {
                ruleListsByExtensionID[manifest.id] = compiledLists
            }
            if !errors.isEmpty {
                errorsByExtensionID[manifest.id] = errors.joined(separator: "\n")
            }
        }

        saveState()

        return CompiledRuleSetBundle(
            ruleListsByExtensionID: ruleListsByExtensionID,
            errorsByExtensionID: errorsByExtensionID
        )
    }

    private func shouldCompile(_ spec: ContentBlockerSpec, for extensionID: String) -> Bool {
        if extensionID == "com.wheel.adblock" && !AppSettings.shared.adBlockerEnabled {
            return false
        }

        switch spec.sourceType {
        case .local:
            return spec.defaultEnabled
        case .remote:
            let subscriptionID = builtInSubscriptionID(extensionID: extensionID, specID: spec.id)
            return subscriptions.first(where: { $0.id == subscriptionID })?.isEnabled ?? spec.defaultEnabled
        }
    }

    private func effectiveEnabled(for spec: ContentBlockerSpec, existing: FilterListSubscriptionState?) -> Bool {
        switch spec.id {
        case "easylist":
            return AppSettings.shared.adBlockEasyListEnabled
        case "easyprivacy":
            return AppSettings.shared.adBlockEasyPrivacyEnabled
        case "fanboy-annoyances":
            return AppSettings.shared.adBlockFanboyAnnoyancesEnabled
        default:
            return existing?.isEnabled ?? spec.defaultEnabled
        }
    }

    private func syncBuiltInToggleIfNeeded(for subscription: FilterListSubscriptionState) {
        guard !subscription.isCustom else { return }
        switch subscription.id {
        case builtInSubscriptionID(extensionID: "com.wheel.adblock", specID: "easylist"):
            AppSettings.shared.adBlockEasyListEnabled = subscription.isEnabled
        case builtInSubscriptionID(extensionID: "com.wheel.adblock", specID: "easyprivacy"):
            AppSettings.shared.adBlockEasyPrivacyEnabled = subscription.isEnabled
        case builtInSubscriptionID(extensionID: "com.wheel.adblock", specID: "fanboy-annoyances"):
            AppSettings.shared.adBlockFanboyAnnoyancesEnabled = subscription.isEnabled
        default:
            break
        }
    }

    @MainActor
    private func refreshSubscription(at index: Int, force: Bool) async throws {
        guard subscriptions.indices.contains(index) else { return }
        let sourceURL = subscriptions[index].sourceURL
        guard let url = URL(string: sourceURL),
              url.scheme?.lowercased() == "https" else {
            throw ContentBlockerManagerError.invalidRemoteURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if !force {
            if let etag = subscriptions[index].etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = subscriptions[index].lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ContentBlockerManagerError.invalidResponse
        }

        if httpResponse.statusCode == 304 {
            subscriptions[index].lastSuccessAt = Date()
            subscriptions[index].lastError = nil
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ContentBlockerManagerError.httpFailure(statusCode: httpResponse.statusCode)
        }

        let body = String(decoding: data, as: UTF8.self)
        guard !body.isEmpty else {
            throw ContentBlockerManagerError.emptyResponse
        }

        try body.write(to: rawCacheFileURL(for: subscriptions[index].id), atomically: true, encoding: .utf8)
        subscriptions[index].etag = httpResponse.value(forHTTPHeaderField: "ETag")
        subscriptions[index].lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
        subscriptions[index].checksum = sha256Hex(for: body)
        subscriptions[index].lastSuccessAt = Date()
        subscriptions[index].lastError = nil
    }

    @MainActor
    private func compileLocalRuleList(
        extensionID: String,
        spec: ContentBlockerSpec,
        rootURL: URL,
        allowlistedDomains: [String]
    ) async -> RuleListOutcome {
        guard let relativePath = spec.path else {
            return RuleListOutcome(error: "Missing local blocker path for \(spec.id).")
        }

        let fileURL = rootURL.appendingPathComponent(relativePath)
        guard let filterText = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return RuleListOutcome(error: "Unable to load blocker rules at \(relativePath).")
        }

        let conversion = ABPFilterRuleConverter.convert(
            filterText: filterText,
            allowlistedDomains: allowlistedDomains
        )

        let checksum = sha256Hex(for: filterText + "\n" + allowlistedDomains.joined(separator: ","))
        let identifier = ruleListIdentifier(for: blockerSourceID(extensionID: extensionID, sourceID: spec.id), checksum: checksum)

        if let existing = await lookupRuleList(identifier: identifier) {
            return RuleListOutcome(ruleList: existing, error: nil)
        }

        do {
            try conversion.encodedRuleList.write(
                to: compiledJSONFileURL(for: identifier),
                atomically: true,
                encoding: .utf8
            )
            let compiled = try await compileRuleList(
                identifier: identifier,
                encodedRuleList: conversion.encodedRuleList
            )
            return RuleListOutcome(ruleList: compiled, error: nil)
        } catch {
            return RuleListOutcome(error: "Failed to compile \(spec.name): \(error.localizedDescription)")
        }
    }

    @MainActor
    private func compileRemoteRuleList(
        subscriptionID: String,
        allowlistedDomains: [String]
    ) async -> RuleListOutcome {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscriptionID }) else {
            return RuleListOutcome(error: "Unknown blocker subscription \(subscriptionID).")
        }

        if !FileManager.default.fileExists(atPath: rawCacheFileURL(for: subscriptionID).path) {
            do {
                try await refreshSubscription(at: index, force: false)
            } catch {
                subscriptions[index].lastError = error.localizedDescription
            }
        }

        guard let filterText = try? String(contentsOf: rawCacheFileURL(for: subscriptionID), encoding: .utf8) else {
            return RuleListOutcome(error: "No cached rules available for \(subscriptions[index].name).")
        }

        let combinedChecksum = sha256Hex(for: filterText + "\n" + allowlistedDomains.joined(separator: ","))
        if subscriptions[index].lastCompiledChecksum == combinedChecksum,
           let identifier = subscriptions[index].lastCompiledIdentifier,
           let existing = await lookupRuleList(identifier: identifier) {
            return RuleListOutcome(ruleList: existing, error: subscriptions[index].lastError)
        }

        let conversion = ABPFilterRuleConverter.convert(
            filterText: filterText,
            allowlistedDomains: allowlistedDomains
        )
        let identifier = ruleListIdentifier(for: subscriptionID, checksum: combinedChecksum)

        do {
            try conversion.encodedRuleList.write(
                to: compiledJSONFileURL(for: identifier),
                atomically: true,
                encoding: .utf8
            )

            let compiled = try await compileRuleList(
                identifier: identifier,
                encodedRuleList: conversion.encodedRuleList
            )

            subscriptions[index].lastCompiledChecksum = combinedChecksum
            subscriptions[index].lastCompiledIdentifier = identifier
            subscriptions[index].lastError = nil

            return RuleListOutcome(ruleList: compiled, error: nil)
        } catch {
            if let fallbackIdentifier = subscriptions[index].lastCompiledIdentifier,
               let fallback = await lookupRuleList(identifier: fallbackIdentifier) {
                subscriptions[index].lastError = "Using cached \(subscriptions[index].name) rules because recompilation failed: \(error.localizedDescription)"
                return RuleListOutcome(ruleList: fallback, error: subscriptions[index].lastError)
            }

            subscriptions[index].lastError = error.localizedDescription
            return RuleListOutcome(error: "Failed to compile \(subscriptions[index].name): \(error.localizedDescription)")
        }
    }

    private func builtInSubscriptionID(extensionID: String, specID: String) -> String {
        "builtin:\(extensionID):\(specID)"
    }

    private func blockerSourceID(extensionID: String, sourceID: String) -> String {
        "\(extensionID):\(sourceID)"
    }

    private func cacheFileName(for id: String, pathExtension: String) -> String {
        let sanitized = id.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(String(scalar))
            }
            return "_"
        }
        return String(sanitized) + "." + pathExtension
    }

    private func rawCacheFileURL(for subscriptionID: String) -> URL {
        cacheDirectoryURL.appendingPathComponent(cacheFileName(for: subscriptionID, pathExtension: "txt"))
    }

    private func compiledJSONFileURL(for identifier: String) -> URL {
        cacheDirectoryURL.appendingPathComponent(cacheFileName(for: identifier, pathExtension: "json"))
    }

    private func ruleListIdentifier(for sourceID: String, checksum: String) -> String {
        "wheel.\(sourceID).\(checksum)"
    }

    private func loadState() {
        guard let decoded = try? stateStore.load() else {
            return
        }
        subscriptions = decoded.subscriptions
    }

    private func saveState() {
        let state = PersistedState(subscriptions: subscriptions)
        try? stateStore.save(state)
    }

    private func sha256Hex(for input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private func compileRuleList(identifier: String, encodedRuleList: String) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            ruleListStore.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encodedRuleList
            ) { ruleList, error in
                if let ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: error ?? ContentBlockerManagerError.compilationFailed)
                }
            }
        }
    }

    @MainActor
    private func lookupRuleList(identifier: String) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            ruleListStore.lookUpContentRuleList(forIdentifier: identifier) { ruleList, _ in
                continuation.resume(returning: ruleList)
            }
        }
    }
}

private struct RuleListOutcome {
    let ruleList: WKContentRuleList?
    let error: String?

    init(ruleList: WKContentRuleList? = nil, error: String?) {
        self.ruleList = ruleList
        self.error = error
    }
}

enum ContentBlockerManagerError: LocalizedError {
    case compilationFailed
    case duplicateCustomList
    case emptyResponse
    case httpFailure(statusCode: Int)
    case invalidCustomListURL
    case invalidRemoteURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .compilationFailed:
            return "WebKit rejected the generated content blocker rules."
        case .duplicateCustomList:
            return "That custom filter list is already installed."
        case .emptyResponse:
            return "The remote filter list returned an empty response."
        case .httpFailure(let statusCode):
            return "The remote filter list returned HTTP \(statusCode)."
        case .invalidCustomListURL:
            return "Custom filter lists must use HTTPS URLs."
        case .invalidRemoteURL:
            return "The filter list URL is invalid."
        case .invalidResponse:
            return "The filter list server returned an invalid response."
        }
    }
}
