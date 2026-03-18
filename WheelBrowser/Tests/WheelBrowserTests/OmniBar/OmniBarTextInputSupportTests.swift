import AppKit
import SwiftUI
import Testing
@testable import WheelBrowser

@Suite("OmniBar Text Input Support")
struct OmniBarTextInputSupportTests {
    @MainActor
    private final class StubKeyboardHandler: OmniBarKeyboardHandler {
        var handledCommands: [KeyboardCommand] = []
        var resultForCommand: [KeyboardCommand: Bool] = [:]

        func handleKeyboardCommand(_ command: KeyboardCommand, moduleID: OmniBarModuleID, text: String) -> Bool {
            handledCommands.append(command)
            return resultForCommand[command] ?? false
        }
    }

    @Test("Mention parser extracts a trailing query after whitespace or start of input")
    func mentionParserFindsValidQueries() {
        #expect(OmniBarMentionTriggerParser.query(in: "@hist") == "hist")
        #expect(OmniBarMentionTriggerParser.query(in: "ask @read") == "read")
    }

    @Test("Mention parser ignores inline at-signs and completed mentions")
    func mentionParserRejectsInvalidTriggers() {
        #expect(OmniBarMentionTriggerParser.query(in: "email@test.com") == nil)
        #expect(OmniBarMentionTriggerParser.query(in: "@done now") == nil)
    }

    @MainActor
    @Test("Multiline editor forwards arrow keys to the keyboard handler before falling back to caret movement")
    func multilineEditorForwardsArrowKeys() {
        let handler = StubKeyboardHandler()
        handler.resultForCommand[.moveDown] = true

        var text = "@road"
        var isFocused = false
        let editor = OmniBarTextEditor(
            text: Binding(
                get: { text },
                set: { text = $0 }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            ),
            moduleID: "multiline-test",
            placeholder: "Enter query...",
            supportsMentions: true,
            keyboardHandler: handler,
            onSubmit: {},
            onAtTrigger: { _ in },
            onAtDismiss: {}
        )

        let coordinator = OmniBarTextEditor.Coordinator(editor)
        let textView = OmniBarTextEditor.MultilineTextView()

        #expect(coordinator.textEditor(textView, handleCommand: .moveDown))
        #expect(handler.handledCommands == [.moveDown])
    }

    @MainActor
    @Test("Multiline editor routes Return through the keyboard handler before direct submission")
    func multilineEditorForwardsSubmit() {
        let handler = StubKeyboardHandler()
        handler.resultForCommand[.submit] = true

        var text = "@road"
        var isFocused = false
        var didSubmit = false
        let editor = OmniBarTextEditor(
            text: Binding(
                get: { text },
                set: { text = $0 }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            ),
            moduleID: "multiline-test",
            placeholder: "Enter query...",
            supportsMentions: true,
            keyboardHandler: handler,
            onSubmit: { didSubmit = true },
            onAtTrigger: { _ in },
            onAtDismiss: {}
        )

        let coordinator = OmniBarTextEditor.Coordinator(editor)
        let textView = OmniBarTextEditor.MultilineTextView()

        #expect(coordinator.textEditorShouldSubmit(textView))
        #expect(handler.handledCommands == [.submit])
        #expect(didSubmit == false)
    }

    @MainActor
    @Test("Multiline editor preserves native arrow movement when the keyboard handler does not consume it")
    func multilineEditorFallsBackForUnhandledArrowKeys() {
        let handler = StubKeyboardHandler()

        var text = "plain text"
        var isFocused = false
        let editor = OmniBarTextEditor(
            text: Binding(
                get: { text },
                set: { text = $0 }
            ),
            isFocused: Binding(
                get: { isFocused },
                set: { isFocused = $0 }
            ),
            moduleID: "multiline-test",
            placeholder: "Enter query...",
            supportsMentions: true,
            keyboardHandler: handler,
            onSubmit: {},
            onAtTrigger: { _ in },
            onAtDismiss: {}
        )

        let coordinator = OmniBarTextEditor.Coordinator(editor)
        let textView = OmniBarTextEditor.MultilineTextView()

        #expect(coordinator.textEditor(textView, handleCommand: .moveUp) == false)
        #expect(handler.handledCommands == [.moveUp])
    }
}
