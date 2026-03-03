import SwiftUI

/// Inline editor that replaces a user message bubble for editing.
/// Shows a text area with "Save & Resend" / "Cancel" buttons.
struct InlineMessageEditor: View {
    let originalContent: String
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @State private var editedContent: String

    init(originalContent: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.originalContent = originalContent
        self.onSave = onSave
        self.onCancel = onCancel
        self._editedContent = State(initialValue: originalContent)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Editable text area
            TextEditor(text: $editedContent)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 40, maxHeight: 200)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                )

            // Action buttons
            HStack(spacing: 8) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.system(size: 12, weight: .medium))

                Button(action: {
                    let trimmed = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 12))
                        Text("Save & Resend")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }
}
