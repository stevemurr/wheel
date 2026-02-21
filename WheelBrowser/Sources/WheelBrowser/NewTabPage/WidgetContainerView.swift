import SwiftUI

/// Container view that wraps a widget with edit controls
struct WidgetContainerView: View {
    @ObservedObject var widget: AnyWidget
    let isEditMode: Bool
    let onRemove: () -> Void
    let onSizeChange: (WidgetSize) -> Void

    @State private var isHovered = false
    @State private var showSizeMenu = false

    // Track content updates to force view refresh
    @State private var contentVersion: Int = 0

    var body: some View {
        widget.makeContent()
            .id(contentVersion) // Force view recreation on content change
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .overlay(alignment: .topTrailing) {
                if isEditMode {
                    editOverlay
                }
            }
            .onHover { isHovered = $0 }
            .onReceive(widget.objectWillChange) { _ in
                contentVersion += 1
            }
    }

    private var editOverlay: some View {
        HStack(spacing: 6) {
            // Size picker button
            Menu {
                ForEach(widget.supportedSizes, id: \.self) { size in
                    Button {
                        onSizeChange(size)
                    } label: {
                        HStack {
                            Text(size.displayName)
                            if widget.currentSize == size {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.accentColor))
            }
            .menuStyle(.borderlessButton)

            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.red))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
    }
}
