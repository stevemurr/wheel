import SwiftUI

/// Calendar + daily notes widget
@MainActor
final class DailyNotesWidget: Widget, ObservableObject {
    static let typeIdentifier = "dailyNotes"
    static let displayName = "Daily Notes"
    static let iconName = "calendar.badge.plus"

    let id = UUID()
    @Published var currentSize: WidgetSize = .extraLarge
    @Published var selectedDate: Date = Date()
    @Published var notes: [String: String] = [:] // dateKey -> note text

    private let calendar = Calendar.current

    var supportedSizes: [WidgetSize] {
        [.extraLarge, .large]
    }

    @ViewBuilder
    func makeContent() -> some View {
        DailyNotesWidgetView(
            selectedDate: selectedDate,
            notes: notes,
            datesWithNotes: Set(notes.keys),
            onSelectDate: { [weak self] date in
                self?.selectedDate = date
            },
            onUpdateNote: { [weak self] text in
                self?.updateNote(text: text)
            }
        )
    }

    func refresh() async {}

    // MARK: - Note Management

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func updateNote(text: String) {
        let key = dateKey(for: selectedDate)
        if text.isEmpty {
            notes.removeValue(forKey: key)
        } else {
            notes[key] = text
        }
        saveDebounced()
    }

    func noteForSelectedDate() -> String {
        notes[dateKey(for: selectedDate)] ?? ""
    }

    // MARK: - Persistence

    private var saveTask: Task<Void, Never>?

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
        ["notes": notes]
    }

    func decodeConfiguration(_ data: [String: Any]) {
        if let savedNotes = data["notes"] as? [String: String] {
            notes = savedNotes
        }
    }
}

struct DayInfo {
    let dayNumber: Int
    let date: Date
}

struct DailyNotesWidgetView: View {
    let selectedDate: Date
    let notes: [String: String]
    let datesWithNotes: Set<String>
    let onSelectDate: (Date) -> Void
    let onUpdateNote: (String) -> Void

    private let calendar = Calendar.current

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left: Calendar (60% of width)
                calendarView
                    .frame(width: geometry.size.width * 0.6, height: geometry.size.height)

                Divider()
                    .padding(.vertical, 12)

                // Right: Note editor (remaining space)
                noteEditorView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Calendar View

    private var calendarView: some View {
        VStack(spacing: 8) {
            // Month navigation
            HStack {
                Button {
                    if let newDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
                        onSelectDate(newDate)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYearString)
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    if let newDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
                        onSelectDate(newDate)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(calendar.veryShortWeekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            let days = daysInMonth()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if day.dayNumber == 0 {
                        Color.clear
                            .frame(height: 28)
                    } else {
                        DayCell(
                            day: day,
                            isSelected: isSameDay(day.date, selectedDate),
                            isToday: isSameDay(day.date, Date()),
                            hasNote: datesWithNotes.contains(dateKey(for: day.date))
                        ) {
                            onSelectDate(day.date)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.trailing, 8)
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }

    private func daysInMonth() -> [DayInfo] {
        var days: [DayInfo] = []

        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
              let range = calendar.range(of: .day, in: .month, for: selectedDate) else {
            return days
        }

        let firstWeekday = calendar.component(.weekday, from: monthStart)

        // Empty cells before first day
        for _ in 1..<firstWeekday {
            days.append(DayInfo(dayNumber: 0, date: Date()))
        }

        // Days of month
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(DayInfo(dayNumber: day, date: date))
            }
        }

        // Pad to 42 cells (6 rows) for consistent height
        while days.count < 42 {
            days.append(DayInfo(dayNumber: 0, date: Date()))
        }

        return days
    }

    private func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        calendar.isDate(date1, inSameDayAs: date2)
    }

    // MARK: - Note Editor View

    private var noteEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date header
            Text(selectedDateString)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            // Note text editor
            NoteEditor(
                text: notes[dateKey(for: selectedDate)] ?? "",
                onUpdate: onUpdateNote
            )
        }
        .padding(.leading, 8)
    }

    private var selectedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let day: DayInfo
    let isSelected: Bool
    let isToday: Bool
    let hasNote: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(day.dayNumber)")
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(foregroundColor)

                // Note indicator dot
                Circle()
                    .fill(hasNote ? Color.accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.1))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return .accentColor
        } else {
            return .primary
        }
    }
}

// MARK: - Note Editor

struct NoteEditor: View {
    let text: String
    let onUpdate: (String) -> Void

    @State private var localText: String
    @FocusState private var isFocused: Bool

    init(text: String, onUpdate: @escaping (String) -> Void) {
        self.text = text
        self.onUpdate = onUpdate
        self._localText = State(initialValue: text)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if localText.isEmpty && !isFocused {
                Text("Add a note for this day...")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
            }

            TextEditor(text: $localText)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .onChange(of: localText) { _, newValue in
                    onUpdate(newValue)
                }
                .onChange(of: text) { _, newValue in
                    // Sync when date changes
                    if newValue != localText {
                        localText = newValue
                    }
                }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.1),
                    lineWidth: 1
                )
        }
    }
}
