import SwiftUI

/// Stickies-style widget for multiple quick notes
@MainActor
final class QuickNoteWidget: Widget, ObservableObject {
    static let typeIdentifier = "quickNote"
    static let displayName = "Stickies"
    static let iconName = "note.text"

    let id = UUID()
    @Published var currentSize: WidgetSize = .medium
    @Published var stickies: [Sticky] = []

    struct Sticky: Identifiable, Codable {
        let id: UUID
        var text: String
        var color: StickyColor

        init(id: UUID = UUID(), text: String = "", color: StickyColor = .yellow) {
            self.id = id
            self.text = text
            self.color = color
        }
    }

    enum StickyColor: String, Codable, CaseIterable {
        case yellow, pink, green, blue, purple, orange

        var color: Color {
            switch self {
            case .yellow: return Color(red: 1.0, green: 0.95, blue: 0.7)
            case .pink: return Color(red: 1.0, green: 0.85, blue: 0.9)
            case .green: return Color(red: 0.8, green: 0.95, blue: 0.8)
            case .blue: return Color(red: 0.85, green: 0.92, blue: 1.0)
            case .purple: return Color(red: 0.92, green: 0.87, blue: 1.0)
            case .orange: return Color(red: 1.0, green: 0.9, blue: 0.8)
            }
        }

        var darkColor: Color {
            switch self {
            case .yellow: return Color(red: 0.9, green: 0.85, blue: 0.5)
            case .pink: return Color(red: 0.9, green: 0.7, blue: 0.8)
            case .green: return Color(red: 0.6, green: 0.85, blue: 0.6)
            case .blue: return Color(red: 0.7, green: 0.82, blue: 0.95)
            case .purple: return Color(red: 0.8, green: 0.7, blue: 0.95)
            case .orange: return Color(red: 0.95, green: 0.8, blue: 0.6)
            }
        }
    }

    var supportedSizes: [WidgetSize] {
        [.small, .medium, .large, .wide]
    }

    @ViewBuilder
    func makeContent() -> some View {
        StickiesWidgetView(
            stickies: stickies,
            size: currentSize,
            onAdd: { [weak self] in self?.addSticky() },
            onUpdate: { [weak self] id, text in self?.updateSticky(id: id, text: text) },
            onUpdateColor: { [weak self] id, color in self?.updateStickyColor(id: id, color: color) },
            onDelete: { [weak self] id in self?.deleteSticky(id: id) }
        )
    }

    func refresh() async {}

    // MARK: - Sticky Management

    func addSticky() {
        let colors = StickyColor.allCases
        let color = colors[stickies.count % colors.count]
        stickies.append(Sticky(color: color))
        save()
    }

    func updateSticky(id: UUID, text: String) {
        if let index = stickies.firstIndex(where: { $0.id == id }) {
            stickies[index].text = text
            saveDebounced()
        }
    }

    func updateStickyColor(id: UUID, color: StickyColor) {
        if let index = stickies.firstIndex(where: { $0.id == id }) {
            stickies[index].color = color
            save()
        }
    }

    func deleteSticky(id: UUID) {
        stickies.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private var saveTask: Task<Void, Never>?

    private func save() {
        NewTabPageManager.shared.save()
    }

    private func saveDebounced() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled {
                NewTabPageManager.shared.save()
            }
        }
    }

    func encodeConfiguration() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(stickies),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }
        return ["stickies": json]
    }

    func decodeConfiguration(_ data: [String: Any]) {
        guard let stickiesData = data["stickies"],
              let jsonData = try? JSONSerialization.data(withJSONObject: stickiesData),
              let decoded = try? JSONDecoder().decode([Sticky].self, from: jsonData) else {
            return
        }
        stickies = decoded
    }
}

struct StickiesWidgetView: View {
    let stickies: [QuickNoteWidget.Sticky]
    let size: WidgetSize
    let onAdd: () -> Void
    let onUpdate: (UUID, String) -> Void
    let onUpdateColor: (UUID, QuickNoteWidget.StickyColor) -> Void
    let onDelete: (UUID) -> Void

    private var columns: Int {
        switch size {
        case .small: return 1
        case .medium: return 2
        case .large: return 2
        case .wide, .extraLarge: return 4
        }
    }

    private var maxStickies: Int {
        switch size {
        case .small: return 1
        case .medium: return 2
        case .large: return 4
        case .wide, .extraLarge: return 4
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if stickies.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
                    spacing: 8
                ) {
                    ForEach(stickies.prefix(maxStickies)) { sticky in
                        StickyNoteView(
                            sticky: sticky,
                            compact: size == .small,
                            onUpdate: onUpdate,
                            onUpdateColor: onUpdateColor,
                            onDelete: onDelete
                        )
                    }

                    if stickies.count < maxStickies {
                        addButton
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        Button(action: onAdd) {
            VStack(spacing: 8) {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                Text("Add a sticky")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            VStack {
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .buttonStyle(.plain)
    }
}

struct StickyNoteView: View {
    let sticky: QuickNoteWidget.Sticky
    let compact: Bool
    let onUpdate: (UUID, String) -> Void
    let onUpdateColor: (UUID, QuickNoteWidget.StickyColor) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var text: String
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    /// Text color for sticky notes - always dark since backgrounds are light pastels
    private var stickyTextColor: Color {
        Color(white: 0.1)
    }

    /// Background color adapts slightly for dark mode
    private var stickyBackgroundColor: Color {
        colorScheme == .dark ? sticky.color.darkColor : sticky.color.color
    }

    init(
        sticky: QuickNoteWidget.Sticky,
        compact: Bool,
        onUpdate: @escaping (UUID, String) -> Void,
        onUpdateColor: @escaping (UUID, QuickNoteWidget.StickyColor) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.sticky = sticky
        self.compact = compact
        self.onUpdate = onUpdate
        self.onUpdateColor = onUpdateColor
        self.onDelete = onDelete
        self._text = State(initialValue: sticky.text)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 4) {
                // Color picker
                Menu {
                    ForEach(QuickNoteWidget.StickyColor.allCases, id: \.self) { color in
                        Button {
                            onUpdateColor(sticky.id, color)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 12, height: 12)
                                Text(color.rawValue.capitalized)
                                if sticky.color == color {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 9))
                        .foregroundStyle(stickyTextColor.opacity(0.5))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 16)
                .opacity(isHovered || isFocused ? 1 : 0)

                Spacer()

                // Delete button
                Button {
                    onDelete(sticky.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(stickyTextColor.opacity(0.5))
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isFocused ? 1 : 0)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .frame(height: 16)

            // Text area
            ZStack(alignment: .topLeading) {
                if text.isEmpty && !isFocused {
                    Text("Note...")
                        .font(.system(size: compact ? 11 : 12))
                        .foregroundStyle(stickyTextColor.opacity(0.3))
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                }

                TextEditor(text: $text)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(stickyTextColor.opacity(0.85))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in
                        onUpdate(sticky.id, newValue)
                    }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(stickyBackgroundColor)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(sticky.color.darkColor, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
    }
}
