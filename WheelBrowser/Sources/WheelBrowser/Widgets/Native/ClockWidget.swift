import SwiftUI

/// Clock widget displaying current time
@MainActor
final class ClockWidget: Widget, ObservableObject {
    static let typeIdentifier = "clock"
    static let displayName = "Clock"
    static let iconName = "clock.fill"

    let id = UUID()
    @Published var currentSize: WidgetSize = .small
    @Published var currentTime = Date()

    private var timer: Timer?

    var supportedSizes: [WidgetSize] {
        [.small, .medium]
    }

    init() {
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    @ViewBuilder
    func makeContent() -> some View {
        ClockWidgetView(currentTime: currentTime, size: currentSize)
    }

    func refresh() async {
        currentTime = Date()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = Date()
            }
        }
    }
}

struct ClockWidgetView: View {
    let currentTime: Date
    let size: WidgetSize

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }

    private var ampmFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }

    var body: some View {
        VStack(spacing: size == .small ? 4 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(timeFormatter.string(from: currentTime))
                    .font(.system(size: size == .small ? 32 : 48, weight: .light, design: .rounded))
                    .monospacedDigit()

                Text(ampmFormatter.string(from: currentTime))
                    .font(.system(size: size == .small ? 14 : 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if size != .small {
                Text(dateFormatter.string(from: currentTime))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
