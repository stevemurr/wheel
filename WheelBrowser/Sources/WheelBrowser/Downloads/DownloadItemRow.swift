import SwiftUI
import AppKit

struct DownloadItemRow: View {
    let item: DownloadItem
    let manager: DownloadManager
    @State private var isHovering = false

    private var fileExtension: String {
        (item.filename as NSString).pathExtension.lowercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            // File icon (28x28 to match other panels)
            fileIcon
                .frame(width: 28, height: 28)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                statusSubtitle
            }

            Spacer()

            // Right side: status badge or action buttons
            rightIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHovering = hovering
            }
        }
        .modifier(PointerCursorModifier())
    }

    @ViewBuilder
    private var fileIcon: some View {
        let (iconName, iconColor) = iconForExtension(fileExtension)

        Image(systemName: iconName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor)
            )
    }

    private func iconForExtension(_ ext: String) -> (String, Color) {
        switch ext {
        case "pdf":
            return ("doc.fill", .red)
        case "zip", "rar", "7z", "tar", "gz":
            return ("archivebox.fill", .brown)
        case "jpg", "jpeg", "png", "gif", "webp", "heic":
            return ("photo.fill", .blue)
        case "mp4", "mov", "avi", "mkv", "webm":
            return ("film.fill", .purple)
        case "mp3", "wav", "flac", "aac", "m4a":
            return ("music.note", .pink)
        case "doc", "docx":
            return ("doc.text.fill", .blue)
        case "xls", "xlsx":
            return ("tablecells.fill", .green)
        case "dmg", "pkg":
            return ("shippingbox.fill", .gray)
        default:
            return ("doc.fill", .secondary)
        }
    }

    @ViewBuilder
    private var statusSubtitle: some View {
        switch item.status {
        case .downloading:
            HStack(spacing: 6) {
                ProgressView(value: item.progress)
                    .frame(width: 80)
                Text(item.formattedSize)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        case .completed:
            if let size = item.completedSize {
                Text(size)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("Completed")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        case .failed(let error):
            Text(error)
                .font(.system(size: 11))
                .foregroundColor(.red.opacity(0.8))
                .lineLimit(1)
        case .cancelled:
            Text("Cancelled")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var rightIndicator: some View {
        switch item.status {
        case .downloading:
            // Progress percentage badge
            Text("\(Int(item.progress * 100))%")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.1))
                )

        case .completed:
            // Action buttons in compact style
            HStack(spacing: 4) {
                Button(action: { manager.openFile(item) }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
                .help("Open")

                Button(action: { manager.revealInFinder(item) }) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }

        case .failed:
            // Error badge
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text("Failed")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.1))
            )

        case .cancelled:
            // Cancelled badge
            Text("Cancelled")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
        }
    }
}

// MARK: - Pointer Cursor Modifier

/// A view modifier that changes the cursor to a pointing hand when hovering
struct PointerCursorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(
            PointerCursorView()
        )
    }
}

/// NSViewRepresentable that sets up a tracking area for cursor changes
struct PointerCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class TrackingView: NSView {
        var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let existingArea = trackingArea {
                removeTrackingArea(existingArea)
            }

            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
            trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(trackingArea!)
        }

        override func mouseEntered(with event: NSEvent) {
            NSCursor.pointingHand.set()
        }

        override func mouseExited(with event: NSEvent) {
            NSCursor.arrow.set()
        }
    }
}
