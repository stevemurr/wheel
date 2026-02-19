import SwiftUI
import AppKit

/// Widget for launching Apple Shortcuts
@MainActor
final class ShortcutsWidget: Widget, ObservableObject {
    static let typeIdentifier = "shortcuts"
    static let displayName = "Shortcuts"
    static let iconName = "command.square"

    let id = UUID()
    @Published var currentSize: WidgetSize = .medium
    @Published var shortcuts: [ShortcutItem] = []

    struct ShortcutItem: Identifiable, Codable {
        let id: UUID
        var name: String
        var color: ShortcutColor

        init(id: UUID = UUID(), name: String, color: ShortcutColor = .blue) {
            self.id = id
            self.name = name
            self.color = color
        }
    }

    enum ShortcutColor: String, Codable, CaseIterable {
        case red, orange, yellow, green, blue, purple, pink, gray

        var color: Color {
            switch self {
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .blue: return .blue
            case .purple: return .purple
            case .pink: return .pink
            case .gray: return .gray
            }
        }
    }

    var supportedSizes: [WidgetSize] {
        [.small, .medium, .large]
    }

    @ViewBuilder
    func makeContent() -> some View {
        ShortcutsWidgetView(
            shortcuts: shortcuts,
            size: currentSize,
            onAdd: { [weak self] name, color in
                self?.addShortcut(name: name, color: color)
            },
            onRemove: { [weak self] id in
                self?.removeShortcut(id: id)
            }
        )
    }

    func refresh() async {
        // No external data to refresh
    }

    func addShortcut(name: String, color: ShortcutColor) {
        let item = ShortcutItem(name: name, color: color)
        shortcuts.append(item)
        NewTabPageManager.shared.save()
    }

    func removeShortcut(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        NewTabPageManager.shared.save()
    }

    // MARK: - Configuration Persistence

    func encodeConfiguration() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(shortcuts),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }
        return ["shortcuts": json]
    }

    func decodeConfiguration(_ data: [String: Any]) {
        guard let shortcutsData = data["shortcuts"],
              let jsonData = try? JSONSerialization.data(withJSONObject: shortcutsData),
              let decoded = try? JSONDecoder().decode([ShortcutItem].self, from: jsonData) else {
            return
        }
        shortcuts = decoded
    }
}

struct ShortcutsWidgetView: View {
    let shortcuts: [ShortcutsWidget.ShortcutItem]
    let size: WidgetSize
    let onAdd: (String, ShortcutsWidget.ShortcutColor) -> Void
    let onRemove: (UUID) -> Void

    @State private var showAddSheet = false
    @State private var isEditing = false

    private var columns: [GridItem] {
        let count = size == .small ? 2 : (size == .large ? 4 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private var maxItems: Int {
        size == .small ? 4 : (size == .large ? 8 : 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                if size != .small {
                    Text("Shortcuts")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !shortcuts.isEmpty {
                    Button {
                        isEditing.toggle()
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if shortcuts.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(shortcuts.prefix(maxItems)) { shortcut in
                        ShortcutButton(
                            shortcut: shortcut,
                            compact: size == .small,
                            isEditing: isEditing,
                            onRemove: { onRemove(shortcut.id) }
                        )
                    }

                    if shortcuts.count < maxItems {
                        addButton
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showAddSheet) {
            AddShortcutSheet(onAdd: onAdd)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "command.square")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)

            Text("No shortcuts")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("Add Shortcut") {
                showAddSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: size == .small ? 16 : 20))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: size == .small ? 36 : 44)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .buttonStyle(.plain)
    }
}

struct ShortcutButton: View {
    let shortcut: ShortcutsWidget.ShortcutItem
    let compact: Bool
    let isEditing: Bool
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            if isEditing {
                onRemove()
            } else {
                runShortcut()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Image(systemName: "command")
                        .font(.system(size: compact ? 14 : 18, weight: .medium))
                        .foregroundStyle(.white)

                    if !compact {
                        Text(shortcut.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 36 : 44)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(shortcut.color.color.gradient)
                }

                if isEditing {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .red)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .help(shortcut.name)
    }

    private func runShortcut() {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", shortcut.name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }
}

struct AddShortcutSheet: View {
    let onAdd: (String, ShortcutsWidget.ShortcutColor) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedColor: ShortcutsWidget.ShortcutColor = .blue

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Shortcut")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Shortcut Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("e.g. Red Lights", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(ShortcutsWidget.ShortcutColor.allCases, id: \.self) { color in
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(color.color.gradient)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if selectedColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    if !name.isEmpty {
                        onAdd(name, selectedColor)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}
