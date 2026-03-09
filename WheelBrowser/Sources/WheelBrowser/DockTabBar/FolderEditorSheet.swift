import SwiftUI

struct FolderEditorSheet: View {
    let title: String
    let submitLabel: String
    let initialName: String
    let initialColor: String
    let onSubmit: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedColor: String

    init(
        title: String,
        submitLabel: String,
        initialName: String,
        initialColor: String,
        onSubmit: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.submitLabel = submitLabel
        self.initialName = initialName
        self.initialColor = initialColor
        self.onSubmit = onSubmit
        _name = State(initialValue: initialName)
        _selectedColor = State(initialValue: initialColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Folder name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Color")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(28), spacing: 10), count: 5),
                    spacing: 10
                ) {
                    ForEach(TabFolder.availableColors, id: \.self) { colorHex in
                        let isSelected = colorHex == selectedColor
                        Button {
                            selectedColor = colorHex
                        } label: {
                            Circle()
                                .fill(Color(hex: colorHex) ?? .accentColor)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                                        .padding(2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(submitLabel) {
                    onSubmit(name, selectedColor)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
