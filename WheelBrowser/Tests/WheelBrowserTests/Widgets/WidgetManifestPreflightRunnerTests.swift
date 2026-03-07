import Foundation
import Testing
@testable import WheelBrowser

@Suite("WidgetManifestPreflightRunner", .serialized)
struct WidgetManifestPreflightRunnerTests {
    @MainActor
    @Test("Preflight succeeds for a renderable text widget")
    func preflightSucceeds() async throws {
        let manifest = WidgetManifest(
            widgetType: .text,
            config: .text(TextConfig(title: "Greeting", markdown: false)),
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
            returns: "textData",
            ttl: 300,
            prompt: "Show hello"
        )

        let runner = WidgetManifestPreflightRunner(
            readyTimeout: .seconds(2),
            executionTimeout: .seconds(2)
        )

        try await runner.preflight(manifest)
    }

    @MainActor
    @Test("Preflight surfaces runtime widget failures")
    func preflightFailsForBrokenWidget() async {
        let manifest = WidgetManifest(
            widgetType: .text,
            config: .text(TextConfig(title: "Broken", markdown: false)),
            skillChain: [
                WidgetSkillStep(
                    step: 1,
                    skill: .parseJson,
                    params: ["json": AnyCodable("not-json")],
                    outputKey: "bad"
                ),
            ],
            returns: "bad",
            ttl: 300,
            prompt: "Broken"
        )

        let runner = WidgetManifestPreflightRunner(
            readyTimeout: .seconds(2),
            executionTimeout: .seconds(2)
        )

        do {
            try await runner.preflight(manifest)
            Issue.record("Expected widget preflight to fail.")
        } catch let error as WidgetManifestPreflightError {
            guard case .widgetFailed(let message) = error else {
                Issue.record("Expected widgetFailed preflight error.")
                return
            }
            #expect(message.lowercased().contains("json"))
        } catch {
            Issue.record("Expected WidgetManifestPreflightError, got \(error.localizedDescription)")
        }
    }
}
