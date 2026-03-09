import SwiftUI

struct FolderRail: View {
    var browserState: BrowserState
    let onCreateFolder: () -> Void
    let onRenameFolder: (UUID) -> Void

    private var entries: [FolderRailEntry] {
        let loose = FolderRailEntry(folderID: nil, title: "Loose")
        let folders = browserState.folders.map { folder in
            FolderRailEntry(folderID: folder.id, title: folder.name)
        }
        return [loose] + folders
    }

    var body: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -14) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        folderButton(for: entry)
                            .zIndex(zIndex(for: entry, index: index))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }

            addButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
    }

    private func folderButton(for entry: FolderRailEntry) -> some View {
        let isSelected = browserState.activeFolderId == entry.folderID

        return Button {
            browserState.selectFolder(entry.folderID)
        } label: {
            FolderTabView(
                title: entry.title,
                count: browserState.tabCount(in: entry.folderID),
                tabs: browserState.previewTabs(in: entry.folderID),
                accentColor: folderColor(for: entry),
                isSelected: isSelected,
                isLoose: entry.folderID == nil
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let folderID = entry.folderID {
                Button("Rename Folder") {
                    onRenameFolder(folderID)
                }

                Button("Delete Folder", role: .destructive) {
                    browserState.deleteFolder(folderID)
                }
            }
        }
    }

    private var addButton: some View {
        Button(action: onCreateFolder) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.72))
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Create Folder")
    }

    private func folderColor(for entry: FolderRailEntry) -> Color {
        if let folderID = entry.folderID,
           let folder = browserState.folder(for: folderID) {
            return folder.accentColor
        }
        return Color(nsColor: .systemGray)
    }

    private func zIndex(for entry: FolderRailEntry, index: Int) -> Double {
        if browserState.activeFolderId == entry.folderID {
            return 1000
        }
        return Double(entries.count - index)
    }
}

private struct FolderRailEntry: Identifiable {
    let folderID: UUID?
    let title: String

    var id: String {
        folderID?.uuidString ?? "loose"
    }
}

private struct FolderTabView: View {
    let title: String
    let count: Int
    let tabs: [Tab]
    let accentColor: Color
    let isSelected: Bool
    let isLoose: Bool

    private var folderFill: LinearGradient {
        let topColor = accentColor.opacity(isLoose ? 0.14 : 0.2)
        let bottomColor = Color.white.opacity(isSelected ? 0.92 : 0.76)
        return LinearGradient(colors: [topColor, bottomColor], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            FolderTabShape()
                .fill(folderFill)
                .overlay {
                    FolderTabShape()
                        .stroke(isSelected ? accentColor.opacity(0.7) : Color.black.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
                }

            Rectangle()
                .fill(accentColor.opacity(isSelected ? 0.9 : 0.65))
                .frame(width: 60, height: 7)
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 12,
                            bottomLeading: 0,
                            bottomTrailing: 6,
                            topTrailing: 8
                        ),
                        style: .continuous
                    )
                )
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: -6) {
                    ForEach(Array(tabs.prefix(3).enumerated()), id: \.offset) { _, tab in
                        FolderPreviewIcon(tab: tab)
                    }

                    if tabs.isEmpty {
                        Image(systemName: "tray")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(Color.white.opacity(0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .padding(.trailing, 16)
        }
        .frame(width: isSelected ? 154 : 144, height: isSelected ? 62 : 58)
        .offset(y: isSelected ? 0 : 4)
        .shadow(color: accentColor.opacity(isSelected ? 0.16 : 0.08), radius: isSelected ? 12 : 8, x: 0, y: 6)
        .animation(AppAnimation.panelSpring, value: isSelected)
    }
}

private struct FolderPreviewIcon: View {
    let tab: Tab

    var body: some View {
        ZStack {
            if let url = tab.url {
                FaviconPlaceholder(url: url, size: 18, cornerRadius: 5, style: .gradient)
            } else if tab.isChatTab {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.pink.opacity(0.75), .orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.72))

                Image(systemName: "globe")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        )
    }
}

private struct FolderTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 14
        let capWidth = min(rect.width * 0.34, 56)
        let capHeight: CGFloat = 11

        var path = Path()
        path.move(to: CGPoint(x: radius, y: capHeight))
        path.addLine(to: CGPoint(x: capWidth - 12, y: capHeight))
        path.addQuadCurve(
            to: CGPoint(x: capWidth, y: 0),
            control: CGPoint(x: capWidth - 3, y: capHeight * 0.15)
        )
        path.addLine(to: CGPoint(x: rect.width - radius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: radius),
            control: CGPoint(x: rect.width, y: 0)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.width - radius, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - radius),
            control: CGPoint(x: 0, y: rect.height)
        )
        path.addLine(to: CGPoint(x: 0, y: capHeight + radius))
        path.addQuadCurve(
            to: CGPoint(x: radius, y: capHeight),
            control: CGPoint(x: 0, y: capHeight)
        )

        return path
    }
}
