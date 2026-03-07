import Foundation

enum WidgetRuntimeResources {
    static func runtimeDirectoryURL() -> URL? {
        runtimeHTMLURL()?.deletingLastPathComponent()
    }

    static func runtimeHTMLURL() -> URL? {
        Bundle.module.url(forResource: "runtime", withExtension: "html", subdirectory: "WidgetRuntime")
    }

    static func runtimeScriptURL() -> URL? {
        Bundle.module.url(forResource: "runtime", withExtension: "js", subdirectory: "WidgetRuntime")
    }

    static func runtimeStylesURL() -> URL? {
        Bundle.module.url(forResource: "styles", withExtension: "css", subdirectory: "WidgetRuntime")
    }
}
