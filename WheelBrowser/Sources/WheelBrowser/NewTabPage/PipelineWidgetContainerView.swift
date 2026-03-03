import SwiftUI

/// Container for a single pipeline widget with edit mode overlay, loading, and error states.
struct PipelineWidgetContainerView: View {
    let widget: WidgetInstance
    let isEditMode: Bool
    let onRemove: () -> Void
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Title bar
                HStack {
                    Text(widget.spec.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if isHovered && !widget.isLoading && !isEditMode {
                        Button {
                            Task { await widget.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }

                    if widget.isLoading {
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
                editOverlay
            }
        }
        .onHover { isHovered = $0 }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let error = widget.error {
            errorView(error)
        } else if let data = widget.lastData {
            WidgetRendererView(input: data)
        } else if widget.isLoading {
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
                Task { await widget.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding()
    }

    // MARK: - Edit Overlay

    private var editOverlay: some View {
        HStack(spacing: 6) {
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14))
                    .foregroundStyle(.white, .blue)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)
            .opacity(canMoveUp ? 1 : 0.4)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14))
                    .foregroundStyle(.white, .blue)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
            .opacity(canMoveDown ? 1 : 0.4)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, .red)
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
        }
        .offset(x: 8, y: -8)
    }
}
