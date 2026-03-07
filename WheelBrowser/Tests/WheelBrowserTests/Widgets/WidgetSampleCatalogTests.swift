import Testing
@testable import WheelBrowser

@Suite("WidgetSampleCatalog")
struct WidgetSampleCatalogTests {
    @Test("Quick-start samples produce valid manifests")
    func quickStartSamplesValidate() throws {
        for sample in WidgetSampleCatalog.quickStart {
            let manifest = sample.buildManifest()
            let validated = try WidgetManifestValidator.validate(manifest)
            #expect(validated.prompt.isEmpty == false)
        }
    }
}
