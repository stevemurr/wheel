import SwiftUI

/// Container for a single module-based widget on the NTP.
/// Similar to PipelineWidgetContainerView but backed by a ModuleInstance.
struct ModuleWidgetContainerView: View {
    let module: ModuleInstance
    let isEditMode: Bool
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Title bar
                HStack {
                    Text(module.manifest.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if isHovered && !module.isLoading && !isEditMode {
                        Button {
                            refreshModule()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }

                    if module.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Content
                contentArea
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)

            // Edit mode overlay
            if isEditMode {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, .red)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .offset(x: 8, y: -8)
            }
        }
        .onHover { isHovered = $0 }
        .onAppear {
            if module.lastData == nil && !module.isLoading {
                refreshModule()
            }
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let error = module.error {
            errorView(error)
        } else if let data = module.lastData {
            WidgetRendererView(input: data)
        } else if module.isLoading {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding()
        } else {
            Text("No data")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button("Retry") {
                refreshModule()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding()
    }

    // MARK: - Execution

    private func refreshModule() {
        guard let runtime = ModuleInjectionHandler.shared.moduleRuntime else { return }

        module.isLoading = true
        module.error = nil

        Task {
            do {
                let result = try await runtime.executeBackground(moduleId: module.id)
                if let renderDict = result as? [String: Any],
                   let renderInput = RenderInputParser.parse(renderDict) {
                    module.lastData = renderInput
                    module.lastExecuted = Date()
                }
            } catch {
                module.error = error.localizedDescription
            }
            module.isLoading = false
        }
    }
}
