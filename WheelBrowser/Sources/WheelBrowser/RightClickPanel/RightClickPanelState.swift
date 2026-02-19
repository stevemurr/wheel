import SwiftUI

@MainActor
class RightClickPanelState: ObservableObject {
    static let shared = RightClickPanelState()

    @Published var isVisible: Bool = false
    @Published var position: CGPoint = .zero

    private init() {}

    func show(at position: CGPoint) {
        self.position = position
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            isVisible = true
        }
    }

    func hide() {
        withAnimation(.easeOut(duration: 0.15)) {
            isVisible = false
        }
    }

    func toggle(at position: CGPoint) {
        if isVisible {
            hide()
        } else {
            show(at: position)
        }
    }
}
