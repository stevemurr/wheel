import Foundation
import Testing
@testable import WheelBrowser

@Suite("WidgetManifestValidator")
struct WidgetManifestValidatorTests {
    @Test("Decode widget manifest with typed config")
    func decodeManifest() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "version": "1",
          "widgetType": "text",
          "config": {
            "title": "Greeting",
            "markdown": false
          },
          "skillChain": [
            {
              "step": 1,
              "skill": "transform",
              "params": {
                "data": { "content": "Hello" },
                "mapping": { "content": "content" }
              },
              "outputKey": "textData"
            }
          ],
          "returns": "textData",
          "ttl": 300,
          "prompt": "Show hello"
        }
        """

        let manifest = try JSONDecoder().decode(WidgetManifest.self, from: Data(json.utf8))
        guard case .text(let config) = manifest.config else {
            Issue.record("Expected text config")
            return
        }

        #expect(config.title == "Greeting")
        #expect(config.markdown == false)
    }

    @Test("Allowed hosts derived from fetch steps")
    func allowedHosts() throws {
        let manifest = sampleFetchManifest(url: "https://api.example.com/prices")
        let validated = try WidgetManifestValidator.validate(manifest)

        #expect(validated.allowedHosts == ["api.example.com"])
    }

    @Test("Rejects invalid returns")
    func invalidReturns() {
        let manifest = WidgetManifest(
            widgetType: .text,
            config: .text(TextConfig(title: "Broken", markdown: false)),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .transform,
                    params: [
                        "data": AnyCodable(["content": "Hello"]),
                        "mapping": AnyCodable(["content": "content"]),
                    ],
                    outputKey: "textData"
                ),
            ],
            returns: "missing",
            ttl: 300,
            prompt: "Broken"
        )

        #expect(throws: WidgetManifestValidationError.invalidReturns("missing")) {
            try WidgetManifestValidator.validate(manifest)
        }
    }

    @Test("Rejects local fetch URLs")
    func rejectsLocalFetchURL() {
        let manifest = sampleFetchManifest(url: "https://localhost/data")

        #expect(throws: WidgetManifestValidationError.invalidFetchURL("https://localhost/data", "Widget fetches cannot target local or private-network hosts.")) {
            try WidgetManifestValidator.validate(manifest)
        }
    }

    @Test("Rejects dynamic fetch URL refs")
    func rejectsDynamicFetchURLReference() {
        let manifest = WidgetManifest(
            widgetType: .text,
            config: .text(TextConfig(title: "Dynamic", markdown: false)),
            skillChain: [
                WidgetSkillStep(step: 1, skill: .transform, params: [
                    "data": AnyCodable(["url": "https://api.example.com/data"]),
                    "mapping": AnyCodable(["url": "url"]),
                ], outputKey: "source"),
                WidgetSkillStep(step: 2, skill: .fetchUrl, params: [
                    "url": AnyCodable("$source.url"),
                ], outputKey: "raw"),
            ],
            returns: "raw",
            ttl: 300,
            prompt: "Dynamic"
        )

        #expect(throws: WidgetManifestValidationError.invalidFetchURL("$source.url", "fetchUrl URLs must be static so the allowlist can be derived up front.")) {
            try WidgetManifestValidator.validate(manifest)
        }
    }

    @Test("Rejects missing required skill parameters")
    func rejectsMissingSkillParameter() {
        let manifest = WidgetManifest(
            widgetType: .text,
            config: .text(TextConfig(title: "Broken", markdown: false)),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .parseJson,
                    params: [:],
                    outputKey: "json"
                ),
            ],
            returns: "json",
            ttl: 300,
            prompt: "Broken"
        )

        #expect(throws: WidgetManifestValidationError.missingSkillParameter(.parseJson, "json")) {
            try WidgetManifestValidator.validate(manifest)
        }
    }

    @Test("Rejects unresolved references to later steps")
    func rejectsUnresolvedReference() {
        let manifest = WidgetManifest(
            widgetType: .text,
            config: .text(TextConfig(title: "Broken", markdown: false)),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .transform,
                    params: [
                        "data": AnyCodable("$future.value"),
                        "mapping": AnyCodable(["content": "content"]),
                    ],
                    outputKey: "textData"
                ),
                WidgetSkillStep(
                    step: 2,
                    skill: .transform,
                    params: [
                        "data": AnyCodable(["value": "Hello"]),
                        "mapping": AnyCodable(["value": "value"]),
                    ],
                    outputKey: "future"
                ),
            ],
            returns: "textData",
            ttl: 300,
            prompt: "Broken"
        )

        #expect(throws: WidgetManifestValidationError.unresolvedReference(step: 1, reference: "$future.value")) {
            try WidgetManifestValidator.validate(manifest)
        }
    }

    @Test("Rejects negative TTL values")
    func rejectsNegativeTTL() {
        let manifest = sampleFetchManifest(url: "https://api.example.com/prices", ttl: -1)

        #expect(throws: WidgetManifestValidationError.invalidTTL(-1)) {
            try WidgetManifestValidator.validate(manifest)
        }
    }
}

private func sampleFetchManifest(url: String, ttl: Int = 300) -> WidgetManifest {
    WidgetManifest(
        widgetType: .statCard,
        config: .statCard(
            StatCardConfig(
                title: "Price",
                valueField: "value",
                prefix: "$",
                suffix: nil,
                changeField: nil,
                changeIsPercent: nil
            )
        ),
        skillChain: [
            WidgetSkillStep(
                step: 1,
                skill: .fetchUrl,
                params: ["url": AnyCodable(url)],
                outputKey: "raw"
            ),
            WidgetSkillStep(
                step: 2,
                skill: .parseJson,
                params: [
                    "json": AnyCodable("$raw"),
                ],
                outputKey: "json"
            ),
            WidgetSkillStep(
                step: 3,
                skill: .transform,
                params: [
                    "data": AnyCodable("$json"),
                    "mapping": AnyCodable(["value": "value"]),
                ],
                outputKey: "cardData"
            ),
        ],
        returns: "cardData",
        ttl: ttl,
        prompt: "Price widget"
    )
}
