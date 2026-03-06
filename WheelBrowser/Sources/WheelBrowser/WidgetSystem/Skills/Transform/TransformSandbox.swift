import Foundation
import JavaScriptCore

/// Sandboxed JavaScriptCore environment for executing transform skills.
/// Strips dangerous globals and loads the pure-JS transform runtime.
final class TransformSandbox: @unchecked Sendable {
    private let context: JSContext
    private let lock = NSLock()

    init() {
        let ctx = JSContext()!

        // Strip dangerous globals
        let dangerousGlobals = [
            "fetch", "XMLHttpRequest", "WebSocket", "Worker",
            "importScripts", "eval", "Function",
        ]
        for name in dangerousGlobals {
            ctx.setObject(nil, forKeyedSubscript: name as NSString)
        }

        // Load the transform runtime
        if let runtimeURL = Bundle.module.url(forResource: "transform_runtime", withExtension: "js", subdirectory: "WidgetSystem"),
           let runtimeJS = try? String(contentsOf: runtimeURL, encoding: .utf8) {
            ctx.evaluateScript(runtimeJS)
        }

        // Set up error handler
        ctx.exceptionHandler = { _, exception in
            if let exception {
                Log.Widgets.error("JS exception: \(exception)")
            }
        }

        self.context = ctx
    }

    /// Execute a transform skill in the sandbox.
    /// - Parameters:
    ///   - skill: The skill name (sort, filter, map_fields, aggregate)
    ///   - params: Skill-specific parameters
    ///   - input: Input data array from a previous pipeline step
    /// - Returns: Transformed data array
    func execute(skill: SkillName, params: [String: Any], input: Any) throws -> Any {
        lock.lock()
        defer { lock.unlock() }

        let fn = context.objectForKeyedSubscript("widgetTransform")!
        let result = fn.call(withArguments: [skill.rawValue, params, input])

        if let exception = context.exception {
            context.exception = nil
            throw WidgetError.executionFailed(
                stepId: "",
                underlying: TransformError.jsError(exception.toString() ?? "Unknown JS error")
            )
        }

        guard let result, !result.isUndefined, !result.isNull else {
            return input
        }

        return result.toObject() ?? input
    }
}

enum TransformError: LocalizedError {
    case jsError(String)

    var errorDescription: String? {
        switch self {
        case .jsError(let message):
            return "Transform JS error: \(message)"
        }
    }
}
