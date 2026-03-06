import SwiftUI

struct LinkPreviewOverlay: View {
    var state = LinkPreviewState.shared
    let containerSize: CGSize
    let onOpenInTab: (URL) -> Void

    var body: some View {
        if state.isVisible, state.linkURL != nil {
            SummaryWindow(
                state: state,
                containerSize: containerSize,
                onClose: {
                    state.dismiss()
                },
                onSaveToReadingList: {
                    // Handled internally by SummaryWindow
                },
                onCopyURL: {
                    // URL already copied by SummaryWindow button
                },
                onOpenInTab: {
                    if let url = state.linkURL {
                        onOpenInTab(url)
                        state.dismiss()
                    }
                }
            )
        }
    }
}
