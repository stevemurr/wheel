import SwiftUI

private enum WidgetCreationSheetPhase {
    case idle
    case checkingAvailability
    case generatingManifest
    case repairingManifest
    case validatingManifest
    case preflightingWidget
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
        case .preflightingWidget:
            self = .preflightingWidget
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "Ready to create"
        case .checkingAvailability:
            return "Checking model availability"
        case .generatingManifest:
            return "Generating plan"
        case .repairingManifest:
            return "Repairing plan"
        case .validatingManifest:
            return "Compiling and validating"
        case .preflightingWidget:
            return "Running hidden preflight"
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
        case .checkingAvailability, .generatingManifest, .repairingManifest, .validatingManifest, .preflightingWidget, .savingWidget:
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
        case .checkingAvailability, .generatingManifest, .repairingManifest, .validatingManifest, .preflightingWidget, .savingWidget:
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
        case .repairingManifest, .validatingManifest, .preflightingWidget:
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
        case .repairingManifest, .validatingManifest, .preflightingWidget:
            return 2
        case .savingWidget:
            return 3
        case .completed:
            return 4
        }
    }

    var showsSpinner: Bool {
        switch self {
        case .checkingAvailability, .generatingManifest, .repairingManifest, .validatingManifest, .preflightingWidget, .savingWidget:
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

private struct WidgetPromptIdea: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let prompt: String
}

struct WidgetPromptSheet: View {
    let onCreate: @MainActor (WidgetManifest) throws -> Void
    let onDismiss: () -> Void
    private let generator: any WidgetManifestGenerator
    private let promptIdeas: [WidgetPromptIdea] = [
        .init(
            id: "graph",
            title: "Graph",
            systemImage: "chart.xyaxis.line",
            prompt: "Show me AMD stock price over the last 30 days as a line chart"
        ),
        .init(
            id: "time",
            title: "Time",
            systemImage: "clock",
            prompt: "Show me the current time in UTC, New York, and Tokyo"
        ),
        .init(
            id: "list",
            title: "List",
            systemImage: "list.bullet.rectangle.portrait",
            prompt: "Create an agenda list widget with today's meetings and status badges"
        ),
        .init(
            id: "stat",
            title: "Stat",
            systemImage: "rectangle.compress.vertical",
            prompt: "Show me Bitcoin price and 24h change as a compact stat card"
        ),
    ]

    @State private var prompt = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var availability: WheelModelAvailability?
    @State private var phase: WidgetCreationSheetPhase = .idle
    @State private var statusDetail = "Describe a live widget or start with a featured sample."
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
            availability = await WheelModelContextService.shared.availabilityStatus()
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

            Text("Describe a widget in plain language, or start from a featured sample to see the runtime in action.")
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
            Text("Featured Samples")
                .font(.headline)

            Text("A small set of polished examples that show charts, clocks, lists, and compact stats.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            ForEach(WidgetSampleCatalog.featuredQuickStart) { sample in
                sampleCard(sample)
            }
        }
        .frame(width: 320, alignment: .leading)
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

            Text("Generation uses the selected AI model. If the model still misses the schema, the app now retries one automatic repair pass before surfacing the error.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var promptComposer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Describe the widget you want")
                        .font(.headline)

                    Text("Keep it simple: say what data to show and any time range or timezone. Time-series widgets can switch between an instant value and a line graph after creation.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("Prompt Studio", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    composerBadge(
                        title: usesBuiltInTemplate ? "Template Shortcut" : "AI Prompt",
                        systemImage: usesBuiltInTemplate ? "bolt.fill" : "sparkles",
                        tint: usesBuiltInTemplate ? .green : .accentColor
                    )

                    composerBadge(
                        title: trimmedPrompt.isEmpty ? "Start from an example" : "\(trimmedPrompt.count) characters",
                        systemImage: "text.alignleft",
                        tint: .secondary
                    )

                    Spacer()
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.96))

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(promptEditorBorder, lineWidth: 1.2)

                    if prompt.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Show me AMD stock price over the last 30 days as a line chart")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)

                            Text("Mention the data, the layout, and any range or timezone you care about.")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                    }

                    TextEditor(text: $prompt)
                        .font(.system(size: 15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
                .frame(minHeight: 176)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Try one of these starts")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(promptIdeas) { idea in
                                promptIdeaChip(idea)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(16)
            .background(promptComposerBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(promptComposerBorder, lineWidth: 1)
            )
            .shadow(color: Color.accentColor.opacity(0.10), radius: 24, y: 12)

            Text("Want the fastest first success? Add one of the featured samples on the right, then come back to AI prompts.")
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

            Text("Try a more specific prompt, or use a featured sample to confirm the dashboard and fetch runtime are working.")
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(sampleAccentGradient(for: sample))

                    Image(systemName: sample.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(sample.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(sample.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Text(sample.badge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(sampleAccentColor(for: sample))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(sampleAccentColor(for: sample).opacity(0.12), in: Capsule())

                Text(sampleCategory(for: sample))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if let promptHint = sample.promptHint {
                    Button("Load Prompt") {
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(sampleCardBackground(for: sample))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(sampleAccentColor(for: sample).opacity(0.16), lineWidth: 1)
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
        return availability.isAvailable
            ? "\(availability.displayName) is available"
            : "\(availability.displayName) is unavailable"
    }

    private var modelStatusDetail: String {
        guard let availability else {
            return "The create flow will enable once the model check completes."
        }
        return availability.reason ?? "Widget generation uses the currently selected AI model."
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var generateButtonDisabled: Bool {
        trimmedPrompt.isEmpty
            || isWorking
            || (!usesBuiltInTemplate && (availability == nil || availability?.isAvailable == false))
    }

    private var footerHint: String {
        if usesBuiltInTemplate {
            return "This prompt matches a built-in widget shortcut, so it can still work without AI generation."
        }
        if availability?.isAvailable == false {
            return "AI generation is unavailable right now. You can still add a featured sample."
        }
        return "Create from prompt, or add a featured sample that skips AI."
    }

    private var usesBuiltInTemplate: Bool {
        guard !trimmedPrompt.isEmpty else { return false }
        return WidgetPromptTemplateFactory.manifest(for: trimmedPrompt) != nil
            || WidgetPromptPlanFactory.plan(for: trimmedPrompt) != nil
    }

    private var creationSteps: [WidgetCreationStepDescriptor] {
        [
            .init(id: 0, title: "Check model", detail: "Verify the selected model is ready."),
            .init(id: 1, title: "Draft a plan", detail: "Generate a constrained widget plan from your prompt."),
            .init(id: 2, title: "Compile and preflight", detail: "Compile the plan, run it once in a hidden runtime, and retry once if needed."),
            .init(id: 3, title: "Save to dashboard", detail: "Persist the widget and trigger its first render."),
        ]
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private var promptComposerBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.16),
                        Color.orange.opacity(0.09),
                        Color(nsColor: .controlBackgroundColor),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var promptComposerBorder: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.30),
                Color.accentColor.opacity(0.24),
                Color.orange.opacity(0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var promptEditorBorder: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.45),
                Color.orange.opacity(0.24),
                Color.primary.opacity(0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func composerBadge(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func promptIdeaChip(_ idea: WidgetPromptIdea) -> some View {
        Button {
            prompt = idea.prompt
            phase = .idle
            statusDetail = "Prompt loaded from \(idea.title.lowercased()) idea."
            error = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: idea.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(idea.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(idea.prompt)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private func sampleCategory(for sample: WidgetSampleDefinition) -> String {
        switch sample.id {
        case "amd-trend":
            return "Graph"
        case "utc-clock":
            return "Time"
        case "daily-agenda":
            return "List"
        case "bitcoin-price":
            return "Stat"
        case "usd-eur-rate":
            return "Rate"
        case "welcome-note":
            return "Text"
        default:
            return "Sample"
        }
    }

    private func sampleAccentColor(for sample: WidgetSampleDefinition) -> Color {
        switch sample.id {
        case "amd-trend":
            return Color(red: 0.95, green: 0.42, blue: 0.20)
        case "utc-clock":
            return Color(red: 0.20, green: 0.54, blue: 0.94)
        case "daily-agenda":
            return Color(red: 0.22, green: 0.67, blue: 0.42)
        case "bitcoin-price":
            return Color(red: 0.90, green: 0.60, blue: 0.16)
        case "usd-eur-rate":
            return Color(red: 0.28, green: 0.52, blue: 0.88)
        case "welcome-note":
            return Color(red: 0.47, green: 0.50, blue: 0.56)
        default:
            return .accentColor
        }
    }

    private func sampleAccentGradient(for sample: WidgetSampleDefinition) -> LinearGradient {
        let accent = sampleAccentColor(for: sample)
        return LinearGradient(
            colors: [
                accent,
                accent.opacity(0.72),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func sampleCardBackground(for sample: WidgetSampleDefinition) -> LinearGradient {
        let accent = sampleAccentColor(for: sample)
        return LinearGradient(
            colors: [
                accent.opacity(0.14),
                Color(nsColor: .controlBackgroundColor),
                Color(nsColor: .controlBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                await MainActor.run {
                    phase = .preflightingWidget
                    lastActiveStepIndex = 2
                    statusDetail = "Running the sample widget once in a hidden dashboard runtime."
                }
                try await WidgetManifestPreflightRunner.shared.preflight(manifest)
                try await MainActor.run {
                    phase = .savingWidget
                    lastActiveStepIndex = 3
                    statusDetail = "Saving the sample widget and sending it to the dashboard."
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
            return "The selected AI model did not return a usable result."
        case WidgetManifestGenerationError.parseFailed:
            return "The model responded, but the widget response still did not match the expected structure."
        case WidgetManifestGenerationError.validationFailed:
            return "The widget plan compiled, but validation rejected it before it reached the dashboard."
        case WidgetManifestGenerationError.preflightFailed:
            return "The widget compiled, but the hidden preflight run failed before it could be saved."
        default:
            return "Widget creation stopped before the widget could be added."
        }
    }
}
