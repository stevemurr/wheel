import Foundation
import JavaScriptCore

/// Sandboxed JavaScriptCore environment for executing transform skills.
/// Strips dangerous globals and loads the pure-JS transform runtime.
///
/// Uses an actor instead of NSLock to avoid blocking Swift Concurrency cooperative threads.
/// An NSLock.lock() call in an async context holds a cooperative thread hostage, which can
/// starve the thread pool when multiple widget pipelines run transforms concurrently.
actor TransformSandbox {
    private let context: JSContext

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

        // Prevent recovering Function constructor via (function(){}).constructor
        // This is a well-known sandbox escape in JavaScriptCore.
        ctx.evaluateScript("""
            (function() {
                var fp = Object.getPrototypeOf(function(){});
                Object.defineProperty(fp, 'constructor', {
                    value: undefined,
                    writable: false,
                    configurable: false
                });
            })();
        """)

        // Load the transform runtime — fatal if missing, as all transforms depend on it
        guard let runtimeURL = Bundle.module.url(forResource: "transform_runtime", withExtension: "js", subdirectory: "WidgetSystem"),
              let runtimeJS = try? String(contentsOf: runtimeURL) else {
            fatalError("TransformSandbox: failed to load transform_runtime.js from bundle — transform skills will not work")
        }
        ctx.evaluateScript(runtimeJS)

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
        guard let fn = context.objectForKeyedSubscript("widgetTransform"),
              !fn.isUndefined else {
            throw WidgetError.executionFailed(
                stepId: "",
                underlying: TransformError.jsError("widgetTransform function is not defined — transform runtime failed to load")
            )
        }
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
