import SwiftUI

/// Modal sheet for creating a new widget via natural language prompt.
struct WidgetPromptSheet: View {
    let store: WidgetStore
    let onDismiss: () -> Void

    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var previewSpec: WidgetPipelineSpec?
    @State private var previewResult: RenderInput?
    @State private var error: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Create Widget")
                .font(.headline)

            Spacer()

            Button("Cancel") {
                dismiss()
                onDismiss()
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let previewResult, let previewSpec {
            previewView(spec: previewSpec, result: previewResult)
        } else {
            promptInput
        }
    }

    // MARK: - Prompt Input

    private var promptInput: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Describe the widget you want:")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("e.g., Show top posts from r/swift sorted by score", text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { generateWidget() }
                    .onChange(of: prompt) { _, _ in
                        error = nil
                    }
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            HStack {
                Spacer()

                Button(action: generateWidget) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("Generate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
                .accessibilityLabel(isGenerating ? "Generating widget" : "Generate")
            }
        }
        .padding()
    }

    // MARK: - Preview

    private func previewView(spec: WidgetPipelineSpec, result: RenderInput) -> some View {
        VStack(spacing: 16) {
            Text(spec.title)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            WidgetRendererView(input: result)
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

            HStack {
                Button("Back") {
                    previewSpec = nil
                    previewResult = nil
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Add to Dashboard") {
                    store.addWidget(spec: spec)
                    dismiss()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Generation

    private func generateWidget() {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isGenerating = true
        error = nil

        Task {
            do {
                let settings = AppSettings.shared
                guard let baseURL = settings.llmBaseURL else {
                    throw WidgetError.specGenerationFailed("LLM endpoint not configured")
                }

                let client = OpenAICompatibleClient(
                    baseURL: baseURL,
                    apiKey: settings.useAPIKey ? settings.llmAPIKey : nil
                )
                let retrying = RetryingLLMClient(wrapping: client)
                let registry = SkillRegistry.createDefault()
                let generator = WidgetSpecGenerator(llmClient: retrying, registry: registry)

                let validatedSpec = try await generator.generate(prompt: prompt, model: settings.selectedModel)

                // Execute pipeline to get preview
                let executor = PipelineExecutor(registry: registry)
                let result = try await executor.execute(validatedSpec)

                await MainActor.run {
                    previewSpec = validatedSpec.spec
                    previewResult = result
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}
