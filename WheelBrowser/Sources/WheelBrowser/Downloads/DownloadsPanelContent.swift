import SwiftUI

/// Downloads panel body displayed inside OmniPanel
struct DownloadsPanelContent: View {
    var manager: DownloadManager

    var body: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(spacing: 2) {
                if manager.downloads.isEmpty {
                    OmniPanelEmptyState(
                        icon: "arrow.down.to.line",
                        title: "No downloads yet",
                        subtitle: "Downloads will appear here"
                    )
                    .padding(.top, 30)
                } else {
                    ForEach(manager.downloads) { item in
                        DownloadItemRow(item: item, manager: manager)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(minHeight: 80)
    }
}
