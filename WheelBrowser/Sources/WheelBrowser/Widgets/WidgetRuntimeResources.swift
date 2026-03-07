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

    static func inlineRuntimeHTML() throws -> String {
        guard let scriptURL = runtimeScriptURL(),
              let stylesURL = runtimeStylesURL() else {
            throw WidgetRuntimeResourceError.missingResource
        }

        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let styles = try String(contentsOf: stylesURL, encoding: .utf8)

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Wheel Widget Runtime</title>
          <style>\(styles)</style>
        </head>
        <body>
          <main id="dashboard" class="dashboard"></main>
          <script>\(script)</script>
        </body>
        </html>
        """
    }
}

enum WidgetRuntimeResourceError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "Widget runtime resources are missing from the app bundle."
        }
    }
}
