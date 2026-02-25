import SwiftUI
import Combine

/// Clock widget displaying current time
@MainActor
final class ClockWidget: Widget, ObservableObject {
    static let typeIdentifier = "clock"
    static let displayName = "Clock"
    static let iconName = "clock.fill"

    let id = UUID()
    @Published var currentSize: WidgetSize = .small
    @Published var currentTime = Date()

    private var cancellable: AnyCancellable?

    var supportedSizes: [WidgetSize] {
        [.small, .medium]
    }

    init() {
        startTimer()
    }

    @ViewBuilder
    func makeContent() -> some View {
        ClockWidgetView(currentTime: currentTime, size: currentSize)
    }

    func refresh() async {
        currentTime = Date()
    }

    private func startTimer() {
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.currentTime = Date()
            }
    }
}

struct ClockWidgetView: View {
    let currentTime: Date
    let size: WidgetSize

    var body: some View {
        VStack(spacing: size == .small ? 4 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(DateFormatterCache.clockTime(from: currentTime))
                    .font(.system(size: size == .small ? 32 : 48, weight: .light, design: .rounded))
                    .monospacedDigit()

                Text(DateFormatterCache.clockAmPm(from: currentTime))
                    .font(.system(size: size == .small ? 14 : 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if size != .small {
                Text(DateFormatterCache.clockFullDate(from: currentTime))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
