import Foundation
import Testing
@testable import WheelBrowser

@Suite("ExtensionRegistry Tests")
@MainActor
struct ExtensionRegistryTests {
    @Test("Bootstrap loads the initial runtime snapshot once before later browser surfaces mount")
    func bootstrapLoadsInitialRuntimeSnapshotOnce() async throws {
        AppSettings.shared.extensionsEnabled = true
        AppSettings.shared.adBlockerEnabled = true

        let tempRoot = try ExtensionTestSupport.makeTemporaryDirectory()
        let bundledRoot = tempRoot.appendingPathComponent("bundled", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledRoot, withIntermediateDirectories: true)

        try ExtensionTestSupport.makeLocalExtension(
            in: bundledRoot,
            folderName: "bundled",
            extensionID: "com.example.bootstrap"
        )

        let blockerManager = ContentBlockerManager(
            stateFileURL: tempRoot.appendingPathComponent("filter_lists.json"),
            cacheDirectoryURL: tempRoot.appendingPathComponent("cache", isDirectory: true)
        )
        let registry = ExtensionRegistry(
            bundledExtensionsURL: bundledRoot,
            sideloadedExtensionsURL: tempRoot.appendingPathComponent("empty-sideloads", isDirectory: true),
            stateFileURL: tempRoot.appendingPathComponent("extensions.json"),
            contentBlockerManager: blockerManager
        )

        var updateCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .extensionRuntimeDidUpdate,
            object: registry,
            queue: nil
        ) { _ in
            updateCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        await registry.bootstrapRuntimeIfNeeded()
        let bootstrappedSnapshot = registry.activeSnapshot()
        await registry.bootstrapRuntimeIfNeeded()

        #expect(registry.hasCompletedInitialRuntimeBootstrap)
        #expect(!bootstrappedSnapshot.userScripts.isEmpty)
        #expect(!bootstrappedSnapshot.contentRuleLists.isEmpty)
        #expect(updateCount == 1)
    }

    @Test("Reload posts runtime updates only when the effective webview configuration changes")
    func reloadSkipsNoOpRuntimeUpdates() async throws {
        AppSettings.shared.extensionsEnabled = true
        AppSettings.shared.adBlockerEnabled = true

        let tempRoot = try ExtensionTestSupport.makeTemporaryDirectory()
        let bundledRoot = tempRoot.appendingPathComponent("bundled", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledRoot, withIntermediateDirectories: true)

        try ExtensionTestSupport.makeLocalExtension(
            in: bundledRoot,
            folderName: "bundled",
            extensionID: "com.example.duplicate"
        )

        let blockerManager = ContentBlockerManager(
            stateFileURL: tempRoot.appendingPathComponent("filter_lists.json"),
            cacheDirectoryURL: tempRoot.appendingPathComponent("cache", isDirectory: true)
        )
        let registry = ExtensionRegistry(
            bundledExtensionsURL: bundledRoot,
            sideloadedExtensionsURL: tempRoot.appendingPathComponent("empty-sideloads", isDirectory: true),
            stateFileURL: tempRoot.appendingPathComponent("extensions.json"),
            contentBlockerManager: blockerManager
        )

        var updateCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .extensionRuntimeDidUpdate,
            object: registry,
            queue: nil
        ) { _ in
            updateCount += 1
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        await registry.reload()
        let firstSnapshot = registry.activeSnapshot()
        await registry.reload()
        let secondSnapshot = registry.activeSnapshot()

        #expect(firstSnapshot.userScripts.map(\.id) == secondSnapshot.userScripts.map(\.id))
        #expect(firstSnapshot.userScripts.map(\.source) == secondSnapshot.userScripts.map(\.source))
        #expect(firstSnapshot.contentRuleLists.map(\.identifier) == secondSnapshot.contentRuleLists.map(\.identifier))

        #expect(updateCount == 1)
    }

    @Test("Bundled extension wins over sideloaded duplicate and builds snapshot")
    func bundledExtensionWinsDuplicate() async throws {
        AppSettings.shared.extensionsEnabled = true
        AppSettings.shared.adBlockerEnabled = true

        let tempRoot = try ExtensionTestSupport.makeTemporaryDirectory()
        let bundledRoot = tempRoot.appendingPathComponent("bundled", isDirectory: true)
        let sideloadRoot = tempRoot.appendingPathComponent("sideloaded", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sideloadRoot, withIntermediateDirectories: true)

        try ExtensionTestSupport.makeLocalExtension(
            in: bundledRoot,
            folderName: "bundled",
            extensionID: "com.example.duplicate"
        )
        try ExtensionTestSupport.makeLocalExtension(
            in: sideloadRoot,
            folderName: "sideloaded",
            extensionID: "com.example.duplicate"
        )

        let blockerManager = ContentBlockerManager(
            stateFileURL: tempRoot.appendingPathComponent("filter_lists.json"),
            cacheDirectoryURL: tempRoot.appendingPathComponent("cache", isDirectory: true)
        )
        let registry = ExtensionRegistry(
            bundledExtensionsURL: bundledRoot,
            sideloadedExtensionsURL: sideloadRoot,
            stateFileURL: tempRoot.appendingPathComponent("extensions.json"),
            contentBlockerManager: blockerManager
        )

        await registry.reload()

        let bundled = try #require(registry.installedExtensions.first(where: { $0.source == .bundled }))
        let sideloaded = try #require(registry.installedExtensions.first(where: { $0.source == .sideloaded }))

        #expect(bundled.lastValidationError == nil)
        #expect(sideloaded.lastValidationError?.contains("Duplicate extension ID") == true)
        #expect(!registry.activeSnapshot().userScripts.isEmpty)
        #expect(!registry.activeSnapshot().contentRuleLists.isEmpty)
    }

    @Test("Missing content-script assets invalidate extension discovery")
    func missingAssetsInvalidateExtension() async throws {
        AppSettings.shared.extensionsEnabled = true

        let tempRoot = try ExtensionTestSupport.makeTemporaryDirectory()
        let bundledRoot = tempRoot.appendingPathComponent("bundled", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledRoot, withIntermediateDirectories: true)

        try ExtensionTestSupport.makeLocalExtension(
            in: bundledRoot,
            folderName: "broken",
            extensionID: "com.example.broken",
            missingScriptAsset: true
        )

        let blockerManager = ContentBlockerManager(
            stateFileURL: tempRoot.appendingPathComponent("filter_lists.json"),
            cacheDirectoryURL: tempRoot.appendingPathComponent("cache", isDirectory: true)
        )
        let registry = ExtensionRegistry(
            bundledExtensionsURL: bundledRoot,
            sideloadedExtensionsURL: tempRoot.appendingPathComponent("empty-sideloads", isDirectory: true),
            stateFileURL: tempRoot.appendingPathComponent("extensions.json"),
            contentBlockerManager: blockerManager
        )

        await registry.reload()

        let installedExtension = try #require(registry.installedExtensions.first)
        #expect(installedExtension.lastValidationError?.contains("Missing content script asset") == true)
        #expect(registry.activeSnapshot().userScripts.isEmpty)
    }
}
