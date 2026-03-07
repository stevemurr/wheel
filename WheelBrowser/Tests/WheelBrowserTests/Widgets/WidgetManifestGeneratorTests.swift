import Foundation
import FoundationModels
import Testing
@testable import WheelBrowser

@Suite("WidgetManifestGenerator")
struct WidgetManifestGeneratorTests {
    @Test("Generator converts structured response into validated manifest")
    func generatesManifest() async throws {
        let generator = OnDeviceWidgetManifestGenerator { _, _ in
            GeneratedWidgetManifest(
                id: "22222222-2222-2222-2222-222222222222",
                version: "1",
                widgetType: "text",
                config: GeneratedContent(GeneratedTextConfig(title: "Greeting", markdown: false)),
                skillChain: [
                    GeneratedWidgetSkillStep(
                        step: 1,
                        skill: "transform",
                        params: GeneratedContent(
                            GeneratedTransformParams(
                                data: GeneratedTextData(content: "Hello"),
                                mapping: GeneratedTextMapping(content: "content")
                            )
                        ),
                        outputKey: "textData"
                    ),
                ],
                returns: "textData",
                ttl: 300,
                prompt: "Show hello"
            )
        }

        let manifest = try await generator.generate(prompt: "Show hello")
        #expect(manifest.id == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(manifest.widgetType == WidgetType.text)
        #expect(manifest.returns == "textData")
    }

    @Test("Generator surfaces validation errors")
    func validationFailure() async {
        let generator = OnDeviceWidgetManifestGenerator { _, _ in
            GeneratedWidgetManifest(
                id: nil,
                version: "1",
                widgetType: "text",
                config: GeneratedContent(GeneratedTextConfig(title: "Broken", markdown: false)),
                skillChain: [
                    GeneratedWidgetSkillStep(
                        step: 1,
                        skill: "transform",
                        params: GeneratedContent(
                            GeneratedTransformParams(
                                data: GeneratedTextData(content: "Hello"),
                                mapping: GeneratedTextMapping(content: "content")
                            )
                        ),
                        outputKey: "textData"
                    ),
                ],
                returns: "missing",
                ttl: 300,
                prompt: "Broken"
            )
        }

        await #expect(throws: WidgetManifestGenerationError.validationFailed("Widget returns 'missing' does not match any skill output.")) {
            try await generator.generate(prompt: "Broken")
        }
    }
}

@Generable(description: "Generated text config for widget tests.")
private struct GeneratedTextConfig {
    let title: String
    let markdown: Bool
}

@Generable(description: "Generated transform params for widget tests.")
private struct GeneratedTransformParams {
    let data: GeneratedTextData
    let mapping: GeneratedTextMapping
}

@Generable(description: "Generated text data for widget tests.")
private struct GeneratedTextData {
    let content: String
}

@Generable(description: "Generated text mapping for widget tests.")
private struct GeneratedTextMapping {
    let content: String
}
