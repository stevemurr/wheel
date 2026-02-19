import SwiftUI

struct DockTabBar: View {
    @ObservedObject var browserState: BrowserState
    @State private var hoveredTabId: UUID?

    private let dockPadding: CGFloat = 8
    private let dockCornerRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 6) {
            ForEach(browserState.tabs) { tab in
                DockTabItem(
                    tab: tab,
                    isActive: tab.id == browserState.activeTabId,
                    isHovered: tab.id == hoveredTabId,
                    tabCount: browserState.tabs.count,
                    onSelect: { browserState.selectTab(tab.id) },
                    onClose: { browserState.closeTab(tab.id) }
                )
                .onHover { hovering in
                    hoveredTabId = hovering ? tab.id : nil
                }
            }

            DockAddButton { browserState.addTab() }
        }
        .padding(dockPadding)
        .background(
            RoundedRectangle(cornerRadius: dockCornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: dockCornerRadius)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}
