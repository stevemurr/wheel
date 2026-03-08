import Foundation

enum NoteEditorResources {
    static func editorDirectoryURL() -> URL? {
        editorHTMLURL()?.deletingLastPathComponent()
    }

    static func editorHTMLURL() -> URL? {
        Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "NoteEditor")
    }
}
