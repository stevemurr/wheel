import SwiftUI

private enum WidgetCreationSheetPhase {
    case idle
    case checkingAvailability
    case generatingManifest
    case repairingManifest
    case validatingManifest
    case savingWidget
    case completed
    case failed

    init(progressPhase: WidgetManifestGenerationProgress.Phase) {
        switch progressPhase {
        case .checkingAvailability:
            self = .checkingAvailability
        case .generatingManifest:
            self = .generatingManifest
        case .repairingManifest:
            self = .repairingManifest
        case .validatingManifest:
            self = .validatingManifest
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "Ready to create"
        case .checkingAvailability:
            return "Checking Apple Intelligence"
        case .generatingManifest:
            return "Generating manifest"
        case .repairingManifest:
            return "Repairing manifest"
        case .validatingManifest:
            return "Validating manifest"
        case .savingWidget:
            return "Adding widget"
        case .completed:
            return "Widget added"
        case .failed:
            return "Creation failed"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            return "sparkles"
        case .checkingAvailability, .generatingManifest, .repairingManifest, .validatingManifest, .savingWidget:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .completed:
            return .green
        case .failed:
            return .red
        case .idle:
            return .accentColor
        case .checkingAvailability, .generatingManifest, .repairingManifest, .validatingManifest, .savingWidget:
            return .orange
        }
    }

    var activeStepIndex: Int? {
        switch self {
        case .idle, .completed, .failed:
            return nil
        case .checkingAvailability:
            return 0
        case .generatingManifest:
            return 1
        case .repairingManifest, .validatingManifest:
            return 2
        case .savingWidget:
            return 3
        }
    }

    var completedStepCount: Int {
        switch self {
        case .idle, .checkingAvailability, .failed:
            return 0
        case .generatingManifest:
            return 1
        case .repairingManifest, .validatingManifest:
            return 2
        case .savingWidget:
            return 3
        case .completed:
            return 4
        }
    }

    var showsSpinner: Bool {
        switch self {
        case .checkingAvailability, .generatingManifest, .repairingManifest, .validatingManifest, .savingWidget:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }
}

private enum WidgetCreationStepState {
    case pending
    case active
    case complete
    case failed
}

private struct WidgetCreationStepDescriptor: Identifiable {
    let id: Int
    let title: String
    let detail: String
}

struct WidgetPromptSheet: View {
    let onCreate: @MainActor (WidgetManifest) throws -> Void
    let onDismiss: () -> Void
    private let generator: any WidgetManifestGenerator

    @State private var prompt = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var availability: OnDeviceLLM.AvailabilityStatus?
    @State private var phase: WidgetCreationSheetPhase = .idle
    @State private var statusDetail = "Describe a live widget or start with a quick sample."
    @State private var lastActiveStepIndex: Int?

    @Environment(\.dismiss) private var dismiss

    init(
        onCreate: @escaping @MainActor (WidgetManifest) throws -> Void,
        onDismiss: @escaping () -> Void,
        generator: any WidgetManifestGenerator = OnDeviceWidgetManifestGenerator()
    ) {
        self.onCreate = onCreate
        self.onDismiss = onDismiss
        self.generator = generator
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    primaryColumn
                    quickStartColumn
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(minWidth: 860, minHeight: 600)
        .task {
            guard availability == nil else { return }
            availability = await OnDeviceLLM.shared.availabilityStatus()
        }
        .onChange(of: prompt) { _, _ in
            guard !isWorking else { return }
            if phase == .failed {
                phase = .idle
                statusDetail = "Prompt updated. Ready to try again."
            }
            error = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Create Widget")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button("Cancel") {
                    dismiss()
                    onDismiss()
                }
                .buttonStyle(.plain)
            }

            Text("Generate a live dashboard widget with Apple Intelligence, or add a known-good sample that skips AI entirely.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            modelStatusCard
            promptComposer
            progressCard

            if let error {
                errorCard(error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickStartColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Start")
                .font(.headline)

            Text("These widgets bypass AI generation so you can verify the dashboard, fetch bridge, and runtime immediately.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            ForEach(WidgetSampleCatalog.quickStart) { sample in
                sampleCard(sample)
            }
        }
        .frame(width: 300, alignment: .leading)
    }

    private var modelStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if let availability {
                        if availability.isAvailable {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(modelStatusTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(modelStatusDetail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text("Generation stays on-device. If the model still misses the schema, the app now retries one automatic repair pass before surfacing the error.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var promptComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Describe the widget you want")
                .font(.headline)

            Text("Good prompts mention both the data and the presentation. Example: “Show me Bitcoin price and 24h change as a compact stat card.”")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)

                if prompt.isEmpty {
                    Text("e.g. Show me Bitcoin price and 24h change as a compact stat card")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $prompt)
                    .font(.system(size: 14))
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .frame(minHeight: 150)

            Text("Need a reliable first success? Use a quick-start widget on the right, then come back to AI generation once the runtime is confirmed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: phase.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(phase.tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(phase.title)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if phase.showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(creationSteps) { step in
                    let state = stepState(for: step.id)
                    HStack(alignment: .top, spacing: 12) {
                        stepIcon(for: state)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(step.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Error details", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Text("Try a more specific prompt, or use a quick-start widget to confirm the dashboard and fetch runtime are working.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.12), lineWidth: 1)
        )
    }

    private func sampleCard(_ sample: WidgetSampleDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sample.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(sample.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(sample.badge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            HStack(spacing: 10) {
                if let promptHint = sample.promptHint {
                    Button("Use Prompt") {
                        prompt = promptHint
                        phase = .idle
                        statusDetail = "Prompt loaded from \(sample.title)."
                        error = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                }

                Button("Add Sample") {
                    addSample(sample)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack {
            Text(footerHint)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                dismiss()
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isWorking)

            Button(action: generateWidget) {
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Working…")
                    }
                } else {
                    Label("Generate Widget", systemImage: "sparkles")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(generateButtonDisabled)
        }
        .padding(20)
    }

    private var modelStatusTitle: String {
        guard let availability else {
            return "Checking model availability"
        }
        return availability.isAvailable ? "Apple Intelligence is available" : "Apple Intelligence is unavailable"
    }

    private var modelStatusDetail: String {
        guard let availability else {
            return "The create flow will enable once the on-device model check completes."
        }
        return availability.reason ?? "Widget generation runs on-device and never leaves your Mac."
    }

    private var generateButtonDisabled: Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || isWorking || availability == nil || availability?.isAvailable == false
    }

    private var footerHint: String {
        if availability?.isAvailable == false {
            return "AI generation is unavailable right now. You can still add a quick-start widget."
        }
        return "Create from prompt, or add a quick-start widget that skips AI."
    }

    private var creationSteps: [WidgetCreationStepDescriptor] {
        [
            .init(id: 0, title: "Check on-device model", detail: "Verify Apple Intelligence is ready."),
            .init(id: 1, title: "Draft a manifest", detail: "Generate widget type, config, and skill chain."),
            .init(id: 2, title: "Repair and validate", detail: "Normalize schema and retry once if needed."),
            .init(id: 3, title: "Save to dashboard", detail: "Persist the widget and trigger its first render."),
        ]
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private func stepState(for index: Int) -> WidgetCreationStepState {
        if phase == .completed {
            return .complete
        }

        if phase == .failed, let lastActiveStepIndex {
            if index < lastActiveStepIndex {
                return .complete
            }
            if index == lastActiveStepIndex {
                return .failed
            }
            return .pending
        }

        if index < phase.completedStepCount {
            return .complete
        }

        if phase.activeStepIndex == index {
            return .active
        }

        return .pending
    }

    @ViewBuilder
    private func stepIcon(for state: WidgetCreationStepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .active:
            Image(systemName: "clock.badge")
                .foregroundStyle(.orange)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func generateWidget() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        isWorking = true
        error = nil
        phase = .idle
        statusDetail = "Preparing widget generation."
        lastActiveStepIndex = nil

        Task {
            do {
                let manifest = try await generator.generate(prompt: trimmedPrompt) { progress in
                    await MainActor.run {
                        phase = WidgetCreationSheetPhase(progressPhase: progress.phase)
                        statusDetail = progress.detail
                        lastActiveStepIndex = phase.activeStepIndex
                    }
                }

                try await MainActor.run {
                    phase = .savingWidget
                    lastActiveStepIndex = 3
                    statusDetail = "Saving the widget and sending it to the dashboard."
                    try onCreate(manifest)
                }

                await MainActor.run {
                    phase = .completed
                    statusDetail = "Widget added. It will render in the dashboard now."
                    isWorking = false
                    dismiss()
                    onDismiss()
                }
            } catch {
                Log.Widgets.error("Widget generation failed", error: error)
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.phase = .failed
                    self.statusDetail = failureSummary(for: error)
                    self.isWorking = false
                }
            }
        }
    }

    private func addSample(_ sample: WidgetSampleDefinition) {
        isWorking = true
        error = nil
        phase = .savingWidget
        statusDetail = "Adding the \(sample.title) sample widget."
        lastActiveStepIndex = 3

        Task {
            do {
                let manifest = sample.buildManifest()
                try await MainActor.run {
                    try onCreate(manifest)
                }
                await MainActor.run {
                    phase = .completed
                    statusDetail = "\(sample.title) was added to the dashboard."
                    isWorking = false
                    dismiss()
                    onDismiss()
                }
            } catch {
                Log.Widgets.error("Adding sample widget failed", error: error)
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.phase = .failed
                    self.statusDetail = "The sample widget could not be added."
                    self.isWorking = false
                }
            }
        }
    }

    private func failureSummary(for error: Error) -> String {
        switch error {
        case WidgetManifestGenerationError.llmFailed:
            return "The on-device model did not return a usable result."
        case WidgetManifestGenerationError.parseFailed:
            return "The model responded, but the manifest still did not match the expected schema."
        case WidgetManifestGenerationError.validationFailed:
            return "The manifest was parsed, but validation rejected it before it reached the dashboard."
        default:
            return "Widget creation stopped before the widget could be added."
        }
    }
}
