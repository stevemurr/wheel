import SwiftUI

/// A view modifier that applies a hover background effect for list item buttons
struct HoverableListItemModifier: ViewModifier {
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    @State private var isHovered = false

    init(cornerRadius: CGFloat = 8, horizontalPadding: CGFloat = 8, verticalPadding: CGFloat = 6) {
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            }
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    /// Applies a hoverable list item style with background highlight on hover
    /// - Parameters:
    ///   - cornerRadius: The corner radius of the background (default: 8)
    ///   - horizontalPadding: The horizontal padding (default: 8)
    ///   - verticalPadding: The vertical padding (default: 6)
    func hoverableListItem(
        cornerRadius: CGFloat = 8,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 6
    ) -> some View {
        modifier(HoverableListItemModifier(
            cornerRadius: cornerRadius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        ))
    }
}
