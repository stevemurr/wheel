import SwiftUI

/// Renders a `RenderInput.composite` layout containing child widget views.
struct CompositeWidgetView: View {
    let layout: CompositeLayout
    let children: [RenderInput]

    var body: some View {
        switch layout {
        case .vstack:
            VStack(spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    WidgetRendererView(input: child)
                }
            }
        case .hstack:
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    WidgetRendererView(input: child)
                        .frame(maxWidth: .infinity)
                }
            }
        case .grid2col:
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    WidgetRendererView(input: child)
                }
            }
        }
    }
}
