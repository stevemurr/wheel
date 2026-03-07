import Foundation
@testable import WheelBrowser

enum ExtensionTestSupport {
    static func makeTemporaryDirectory(named name: String = UUID().uuidString) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wheel-extension-tests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    static func makeLocalExtension(
        in rootURL: URL,
        folderName: String,
        extensionID: String,
        scriptPath: String = "scripts/main.js",
        blockerPath: String = "lists/base.txt",
        scriptContents: String = "window.__wheelTestExtension = true;",
        blockerContents: String = "||ads.example.com^",
        missingScriptAsset: Bool = false
    ) throws -> URL {
        let extensionURL = rootURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: extensionURL, withIntermediateDirectories: true)

        if !missingScriptAsset {
            try write(scriptContents, to: extensionURL.appendingPathComponent(scriptPath))
        }
        try write(blockerContents, to: extensionURL.appendingPathComponent(blockerPath))

        let manifest = """
        {
          "id": "\(extensionID)",
          "name": "Test Extension",
          "version": "1.0.0",
          "defaultEnabled": true,
          "capabilities": ["contentBlocking", "contentScripts"],
          "contentBlockers": [
            {
              "id": "base",
              "name": "Base",
              "sourceType": "local",
              "path": "\(blockerPath)",
              "defaultEnabled": true
            }
          ],
          "contentScripts": [
            {
              "id": "script",
              "matches": ["https://*/*"],
              "excludeMatches": [],
              "js": ["\(scriptPath)"],
              "css": [],
              "injectionTime": "documentEnd",
              "allFrames": false
            }
          ]
        }
        """

        try write(manifest, to: extensionURL.appendingPathComponent("extension.json"))
        return extensionURL
    }

    static func makeRemoteExtension(
        extensionID: String,
        remoteURL: String
    ) -> InstalledExtension {
        let manifest = ExtensionManifest(
            id: extensionID,
            name: "Remote Extension",
            version: "1.0.0",
            defaultEnabled: true,
            capabilities: [.contentBlocking],
            contentBlockers: [
                ContentBlockerSpec(
                    id: "remote",
                    name: "Remote List",
                    sourceType: .remote,
                    path: nil,
                    url: remoteURL,
                    defaultEnabled: true
                )
            ],
            contentScripts: []
        )

        return InstalledExtension(
            id: "bundled:\(extensionID)",
            logicalID: extensionID,
            manifest: manifest,
            rootURL: FileManager.default.temporaryDirectory,
            source: .bundled,
            isEnabled: true,
            lastValidationError: nil,
            lastRuntimeError: nil
        )
    }

    static func write(_ contents: String, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
