import SwiftUI

/// Renders a `RenderInput.composite` layout containing child widget views.
struct CompositeWidgetView: View {
    let layout: CompositeLayout
    let children: [RenderInput]

    private struct IdentifiedChild: Identifiable {
        let id: Int
        let input: RenderInput
    }

    private var identifiedChildren: [IdentifiedChild] {
        children.enumerated().map { IdentifiedChild(id: $0.offset, input: $0.element) }
    }

    var body: some View {
        switch layout {
        case .vstack:
            VStack(spacing: 8) {
                ForEach(identifiedChildren) { child in
                    WidgetRendererView(input: child.input)
                }
            }
        case .hstack:
            HStack(alignment: .top, spacing: 8) {
                ForEach(identifiedChildren) { child in
                    WidgetRendererView(input: child.input)
                        .frame(maxWidth: .infinity)
                }
            }
        case .grid2col:
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                ForEach(identifiedChildren) { child in
                    WidgetRendererView(input: child.input)
                }
            }
        }
    }
}
