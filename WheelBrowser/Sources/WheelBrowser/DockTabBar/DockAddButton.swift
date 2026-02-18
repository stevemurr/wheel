import SwiftUI

struct DockAddButton: View {
    let action: () -> Void

    private let size: CGFloat = 44
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                )
        }
        .buttonStyle(.plain)
    }
}
