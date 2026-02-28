import SwiftUI
import Combine

@MainActor
class TabWheelState: ObservableObject {
    static let shared = TabWheelState()

    @Published var isVisible: Bool = false
    @Published var position: CGPoint = .zero
    @Published var rotationAngle: Double = 0.0
    @Published var selectedIndex: Int = 0

    private var accumulatedScroll: CGFloat = 0
    private let trackpadThreshold: CGFloat = 20
    private let mouseWheelThreshold: CGFloat = 1

    // Track the initial tab index when wheel opens
    private var initialTabIndex: Int = 0

    // Callback when selection changes
    var onSelectionChanged: ((Int) -> Void)?

    private init() {}

    func show(at position: CGPoint, initialIndex: Int = 0, tabCount: Int) {
        self.position = position
        self.initialTabIndex = initialIndex
        self.selectedIndex = initialIndex

        // Calculate initial rotation so current tab is at 12 o'clock
        let anglePerTab = tabCount > 0 ? 360.0 / Double(tabCount) : 0
        self.rotationAngle = -Double(initialIndex) * anglePerTab
        self.accumulatedScroll = 0

        withAnimation(AppAnimation.springSnappy) {
            isVisible = true
        }
    }

    func hide() {
        withAnimation(AppAnimation.standardOut) {
            isVisible = false
        }
    }

    func toggle(at position: CGPoint, initialIndex: Int = 0, tabCount: Int) {
        if isVisible {
            hide()
        } else {
            show(at: position, initialIndex: initialIndex, tabCount: tabCount)
        }
    }

    func handleScroll(deltaY: CGFloat, tabCount: Int, isPrecise: Bool = true) {
        guard tabCount > 0 else { return }

        accumulatedScroll += deltaY
        let threshold = isPrecise ? trackpadThreshold : mouseWheelThreshold

        if abs(accumulatedScroll) >= threshold {
            let direction = accumulatedScroll > 0 ? -1 : 1
            let anglePerTab = 360.0 / Double(tabCount)

            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                rotationAngle += Double(direction) * anglePerTab
            }

            accumulatedScroll = 0
            let newIndex = calculateSelectedIndex(tabCount: tabCount)
            if newIndex != selectedIndex {
                selectedIndex = newIndex
                onSelectionChanged?(newIndex)
            }
        }
    }

    private func calculateSelectedIndex(tabCount: Int) -> Int {
        guard tabCount > 0 else { return 0 }

        let anglePerTab = 360.0 / Double(tabCount)
        // Normalize rotation to 0-360 range
        var normalizedAngle = rotationAngle.truncatingRemainder(dividingBy: 360)
        if normalizedAngle < 0 {
            normalizedAngle += 360
        }

        // Calculate which tab is at the top (12 o'clock position)
        // When rotation is 0, tab 0 is at top
        // When rotation increases, tabs rotate counter-clockwise, so higher indices come to top
        let index = Int(round(-normalizedAngle / anglePerTab)).nonNegativeModulo(tabCount)
        return index
    }

    /// Reset state when closing
    func reset() {
        rotationAngle = 0.0
        selectedIndex = 0
        accumulatedScroll = 0
        initialTabIndex = 0
    }
}

// MARK: - Helper Extension

private extension Int {
    func nonNegativeModulo(_ divisor: Int) -> Int {
        guard divisor > 0 else { return 0 }
        let result = self % divisor
        return result >= 0 ? result : result + divisor
    }
}
