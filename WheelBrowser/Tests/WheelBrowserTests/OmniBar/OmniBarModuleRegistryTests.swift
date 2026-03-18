import SwiftUI
import Testing
@testable import WheelBrowser

@MainActor
@Suite("OmniBar Module Registry")
struct OmniBarModuleRegistryTests {
    private final class FakeModule: OmniBarModule {
        let id: OmniBarModuleID = "test-module"
        let title = "Test"
        let icon = "hammer"
        let placeholder = "Test module"
        let color = Color.blue

        var activateCount = 0
        var deactivateCount = 0
        var lastInput: String?
        var submitCount = 0
        var handledCommands: [KeyboardCommand] = []

        func activate(in featureModel: OmniBarFeatureModel, reason: OmniBarModuleActivationReason) {
            activateCount += 1
        }

        func deactivate(in featureModel: OmniBarFeatureModel) {
            deactivateCount += 1
        }

        func handleInputChanged(in featureModel: OmniBarFeatureModel, text: String) {
            lastInput = text
        }

        func handleSubmit(in featureModel: OmniBarFeatureModel) {
            submitCount += 1
        }

        func handleKeyboardCommand(_ command: KeyboardCommand, in featureModel: OmniBarFeatureModel, text: String) -> Bool? {
            handledCommands.append(command)
            return false
        }

        func clear(in featureModel: OmniBarFeatureModel) {}
    }

    private func makeFeatureModel(fakeModule: FakeModule) -> OmniBarFeatureModel {
        let browserState = BrowserState()
        let agentManager = AgentManager()
        let agentEngine = AgentEngine(browserState: browserState, settings: AppSettings.shared)
        let registry = OmniBarModuleRegistry(modules: OmniBarModuleRegistry.builtIn().modules + [fakeModule])

        return OmniBarFeatureModel(
            tab: Tab(),
            agentManager: agentManager,
            browserState: browserState,
            agentEngine: agentEngine,
            registry: registry,
            commandCenter: OmniBarCommandCenter()
        )
    }

    @Test("Registered modules receive activation, input, submit, and keyboard events")
    func registeredModuleReceivesFeatureEvents() {
        let fakeModule = FakeModule()
        let featureModel = makeFeatureModel(fakeModule: fakeModule)

        featureModel.isInputFocused = true
        featureModel.setMode(fakeModule.id)
        featureModel.handleModeChange(fakeModule.id)
        featureModel.inputText = "hello"
        featureModel.handleInputTextChange("hello")
        featureModel.handleSubmit()
        _ = featureModel.handleKeyboardCommand(.moveDown, moduleID: fakeModule.id, text: "hello")

        #expect(fakeModule.activateCount == 1)
        #expect(fakeModule.lastInput == "hello")
        #expect(fakeModule.submitCount == 1)
        #expect(fakeModule.handledCommands == [.moveDown])
    }

    @Test("Registry cycles module order using registered IDs")
    func registryUsesRegistrationOrder() {
        let registry = OmniBarModuleRegistry.builtIn()

        #expect(registry.nextID(after: .address) == .semantic)
        #expect(registry.previousID(before: .address) == .readingList)
    }
}
