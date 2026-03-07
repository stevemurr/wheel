import SwiftUI

struct WidgetPromptSheet: View {
    let store: WidgetDashboardStore
    let onDismiss: () -> Void
    private let generator: any WidgetManifestGenerator

    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var error: String?

    @Environment(\.dismiss) private var dismiss

    init(
        store: WidgetDashboardStore,
        onDismiss: @escaping () -> Void,
        generator: any WidgetManifestGenerator = OnDeviceWidgetManifestGenerator()
    ) {
        self.store = store
        self.onDismiss = onDismiss
        self.generator = generator
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 520, minHeight: 320)
    }

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

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Describe the live widget you want to add:")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(
                "e.g. Show me Bitcoin price and 24h change",
                text: $prompt
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { generateWidget() }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
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
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
            }
        }
        .padding()
    }

    private func generateWidget() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        isGenerating = true
        error = nil

        Task {
            do {
                let manifest = try await generator.generate(prompt: trimmedPrompt)
                await MainActor.run {
                    store.add(manifest: manifest)
                    dismiss()
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }
}
