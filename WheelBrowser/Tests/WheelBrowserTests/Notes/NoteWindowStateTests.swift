import Foundation
import Testing
@testable import WheelBrowser

@Suite("NoteWindowState")
@MainActor
struct NoteWindowStateTests {
    @Test("Opening a second note reuses the same window")
    func reusesSingleWindow() {
        let state = NoteWindowState()
        state.containerSize = CGSize(width: 1400, height: 900)

        let first = makeNote(title: "First")
        let second = makeNote(title: "Second")

        state.open(note: first)
        let windowID = try! #require(state.window?.id)
        state.updatePosition(CGPoint(x: 120, y: 140))
        state.updateSize(CGSize(width: 640, height: 720))

        state.open(note: second)

        #expect(state.window?.id == windowID)
        #expect(state.window?.noteID == second.id)
        #expect(state.window?.position == CGPoint(x: 120, y: 140))
        #expect(state.window?.size == CGSize(width: 640, height: 720))
    }

    @Test("Maximize toggles and restores the previous frame")
    func maximizesAndRestores() {
        let state = NoteWindowState()
        state.containerSize = CGSize(width: 1200, height: 800)

        let note = makeNote(title: "Today")
        state.open(note: note)
        state.updatePosition(CGPoint(x: 80, y: 40))
        state.updateSize(CGSize(width: 580, height: 700))

        state.toggleMaximize()
        #expect(state.window?.isMaximized == true)
        #expect(state.window?.size == CGSize(width: 1200, height: 800))

        state.toggleMaximize()
        #expect(state.window?.isMaximized == false)
        #expect(state.window?.position == CGPoint(x: 80, y: 40))
        #expect(state.window?.size == CGSize(width: 580, height: 700))
    }

    @Test("Closing the note window clears the active item")
    func closesWindow() {
        let state = NoteWindowState()
        state.open(note: makeNote(title: "Scratchpad"))

        state.close()

        #expect(state.window == nil)
    }

    private func makeNote(title: String) -> NoteRecord {
        NoteRecord(
            workspaceID: UUID(),
            kind: .adhoc,
            title: title
        )
    }
}
