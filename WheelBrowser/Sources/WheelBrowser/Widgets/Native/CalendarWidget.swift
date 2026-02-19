import SwiftUI

/// Calendar widget displaying the current month
@MainActor
final class CalendarWidget: Widget, ObservableObject {
    static let typeIdentifier = "calendar"
    static let displayName = "Calendar"
    static let iconName = "calendar"

    let id = UUID()
    @Published var currentSize: WidgetSize = .medium
    @Published var currentDate = Date()

    private var timer: Timer?

    var supportedSizes: [WidgetSize] {
        [.small, .medium, .large]
    }

    init() {
        startMidnightTimer()
    }

    deinit {
        timer?.invalidate()
    }

    @ViewBuilder
    func makeContent() -> some View {
        CalendarWidgetView(currentDate: currentDate, size: currentSize)
    }

    func refresh() async {
        currentDate = Date()
    }

    private func startMidnightTimer() {
        // Update at midnight
        let calendar = Calendar.current
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
           let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow) {
            let interval = midnight.timeIntervalSinceNow
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.currentDate = Date()
                    self?.startMidnightTimer()
                }
            }
        }
    }
}

struct CalendarWidgetView: View {
    let currentDate: Date
    let size: WidgetSize

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    private var currentMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) ?? currentDate
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentDate)
    }

    private var dayOfMonth: Int {
        calendar.component(.day, from: currentDate)
    }

    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: currentDate)
    }

    var body: some View {
        Group {
            switch size {
            case .small:
                compactView
            case .medium, .wide:
                mediumView
            case .large, .extraLarge:
                fullCalendarView
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Small Size: Just today's date

    private var compactView: some View {
        VStack(spacing: 4) {
            Text(dayOfWeek.prefix(3).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)

            Text("\(dayOfMonth)")
                .font(.system(size: 36, weight: .light, design: .rounded))

            Text(monthName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Medium Size: Today + mini calendar

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Today's date
            VStack(spacing: 2) {
                Text(dayOfWeek.prefix(3).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)

                Text("\(dayOfMonth)")
                    .font(.system(size: 32, weight: .light, design: .rounded))
            }
            .frame(width: 60)

            Divider()
                .frame(height: 50)

            // Mini month view
            VStack(alignment: .leading, spacing: 4) {
                Text(monthName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                miniCalendarGrid
            }
        }
    }

    // MARK: - Large Size: Full calendar

    private var fullCalendarView: some View {
        VStack(spacing: 12) {
            // Month header
            Text(monthName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            calendarGrid
        }
    }

    // MARK: - Calendar Grids

    private var miniCalendarGrid: some View {
        let days = daysInMonth()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(days, id: \.self) { day in
                if day == 0 {
                    Text("")
                        .frame(width: 14, height: 14)
                } else {
                    Text("\(day)")
                        .font(.system(size: 9))
                        .foregroundStyle(day == dayOfMonth ? .white : .primary)
                        .frame(width: 14, height: 14)
                        .background {
                            if day == dayOfMonth {
                                Circle()
                                    .fill(Color.accentColor)
                            }
                        }
                }
            }
        }
    }

    private var calendarGrid: some View {
        let days = daysInMonth()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { day in
                if day == 0 {
                    Text("")
                        .frame(height: 24)
                } else {
                    Text("\(day)")
                        .font(.system(size: 12))
                        .foregroundStyle(day == dayOfMonth ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if day == dayOfMonth {
                                Circle()
                                    .fill(Color.accentColor)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Helpers

    private func daysInMonth() -> [Int] {
        var days: [Int] = []

        // Get the first day of the month
        guard let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)),
              let range = calendar.range(of: .day, in: .month, for: currentDate) else {
            return days
        }

        // Get weekday of first day (1 = Sunday, 7 = Saturday)
        let firstWeekday = calendar.component(.weekday, from: firstDay)

        // Add empty slots for days before the first
        for _ in 1..<firstWeekday {
            days.append(0)
        }

        // Add all days of the month
        for day in range {
            days.append(day)
        }

        return days
    }
}
