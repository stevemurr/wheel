import SwiftUI

extension ScrollViewProxy {
    /// Scrolls to the bottom of the scroll view using a standard anchor ID
    /// - Parameters:
    ///   - anchorID: The ID of the anchor view at the bottom (defaults to "bottom")
    ///   - animated: Whether to animate the scroll
    func scrollToBottom(anchorID: String = "bottom", animated: Bool = true) {
        if animated {
            withAnimation(AppAnimation.standard) {
                scrollTo(anchorID, anchor: .bottom)
            }
        } else {
            scrollTo(anchorID, anchor: .bottom)
        }
    }
}
