import Foundation

/// Executes a validated pipeline spec step-by-step, resolving references between steps.
actor PipelineExecutor {
    private let registry: SkillRegistry

    /// Timeout per individual step
    private let stepTimeout: TimeInterval = 30

    init(registry: SkillRegistry) {
        self.registry = registry
    }

    /// Execute a validated pipeline spec and return the final render input.
    func execute(_ validatedSpec: ValidatedSpec) async throws -> RenderInput {
        let spec = validatedSpec.spec
        var context: [String: Any] = [:]

        for (index, step) in spec.pipeline.enumerated() {
            let resolved = try ReferenceResolver.resolve(params: step.params, context: context)

            let output: Any
            do {
                output = try await withTimeout(seconds: stepTimeout) {
                    try await self.registry.execute(skill: step.skill, params: resolved)
                }
            } catch is TimeoutError {
                throw WidgetError.stepTimeout(stepId: step.id)
            } catch let error as WidgetError {
                // Re-wrap with the correct step ID
                switch error {
                case .executionFailed(_, let underlying):
                    throw WidgetError.executionFailed(stepId: step.id, underlying: underlying)
                default:
                    throw error
                }
            } catch {
                throw WidgetError.executionFailed(stepId: step.id, underlying: error)
            }

            context[step.id] = output

            // Last step must return a RenderInput
            if index == spec.pipeline.count - 1 {
                guard let renderInput = output as? RenderInput else {
                    throw WidgetError.renderFailed("Final step '\(step.id)' did not return a RenderInput")
                }
                return renderInput
            }
        }

        throw WidgetError.renderFailed("Pipeline has no steps")
    }
}

// MARK: - Timeout Utility

private struct TimeoutError: Error {}

private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}
