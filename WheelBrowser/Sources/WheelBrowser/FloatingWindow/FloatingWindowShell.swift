import AppKit
import SwiftUI

@MainActor
protocol FloatingWindowItemProtocol: AnyObject, Identifiable {
    var title: String { get set }
    var position: CGPoint { get set }
    var size: CGSize { get set }
    var isMinimized: Bool { get set }
    var isMaximized: Bool { get set }
    var zIndex: Int { get set }
    var preMaximizePosition: CGPoint? { get set }
    var preMaximizeSize: CGSize? { get set }
}

struct FloatingWindowShell<Item: FloatingWindowItemProtocol, Controls: View, WindowContent: View>: View {
    var item: Item
    let containerSize: CGSize
    let onClose: () -> Void
    let onBringToFront: () -> Void
    let onMinimize: () -> Void
    let onToggleMaximize: () -> Void
    let onUpdatePosition: (CGPoint) -> Void
    let onUpdateSize: (CGSize) -> Void
    let controls: Controls
    let windowContent: WindowContent

    private let cornerRadius: CGFloat = 12
    private let titleBarHeight: CGFloat = 36
    private let minSize = CGSize(width: 300, height: 200)
    private let minVisiblePortion: CGFloat = 100

    @State private var isDragging = false
    @State private var dragStartPosition: CGPoint = .zero
    @State private var isResizing = false
    @State private var initialSize: CGSize = .zero
    @State private var initialPosition: CGPoint = .zero

    init(
        item: Item,
        containerSize: CGSize,
        onClose: @escaping () -> Void,
        onBringToFront: @escaping () -> Void,
        onMinimize: @escaping () -> Void,
        onToggleMaximize: @escaping () -> Void,
        onUpdatePosition: @escaping (CGPoint) -> Void,
        onUpdateSize: @escaping (CGSize) -> Void,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder content: () -> WindowContent
    ) {
        self.item = item
        self.containerSize = containerSize
        self.onClose = onClose
        self.onBringToFront = onBringToFront
        self.onMinimize = onMinimize
        self.onToggleMaximize = onToggleMaximize
        self.onUpdatePosition = onUpdatePosition
        self.onUpdateSize = onUpdateSize
        self.controls = controls()
        self.windowContent = content()
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                titleBar
                windowContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: item.size.width, height: item.size.height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 4)

            if !item.isMaximized {
                resizeHandles
            }
        }
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    onBringToFront()
                }
        )
    }

    private var titleBar: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .onHover { hovering in
                    if hovering && !isDragging {
                        NSCursor.openHand.push()
                    } else if !hovering && !isDragging {
                        NSCursor.pop()
                    }
                }

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .separatorColor).opacity(0.5))
                    .frame(width: 36, height: 4)
                    .padding(.top, 6)
                    .allowsHitTesting(false)

                HStack(spacing: 8) {
                    trafficLightButtons
                    Spacer()
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200)
                        .allowsHitTesting(false)
                    Spacer()
                    controls
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
        .frame(height: titleBarHeight)
    }

    private var trafficLightButtons: some View {
        HStack(spacing: 6) {
            TrafficLightButton(color: .red, icon: "xmark", action: onClose)
            TrafficLightButton(color: .yellow, icon: "minus", action: onMinimize)
            TrafficLightButton(
                color: .green,
                icon: item.isMaximized ? "arrow.down.right.and.arrow.up.left" : "plus",
                action: onToggleMaximize
            )
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartPosition = item.position
                    onBringToFront()
                    NSCursor.closedHand.push()
                }

                let newX = dragStartPosition.x + value.translation.width
                let newY = dragStartPosition.y + value.translation.height
                onUpdatePosition(CGPoint(x: clampX(newX), y: clampY(newY)))
            }
            .onEnded { _ in
                isDragging = false
                NSCursor.pop()
            }
    }

    private func clampX(_ x: CGFloat) -> CGFloat {
        let minX = -item.size.width + minVisiblePortion
        let maxX = containerSize.width - minVisiblePortion
        return max(minX, min(x, maxX))
    }

    private func clampY(_ y: CGFloat) -> CGFloat {
        let minY: CGFloat = 0
        let maxY = containerSize.height - minVisiblePortion
        return max(minY, min(y, maxY))
    }

    private var resizeHandles: some View {
        ZStack {
            FloatingResizeHandle(edge: .topLeft)
                .position(x: 0, y: 0)
                .gesture(resizeGesture(edge: .topLeft))

            FloatingResizeHandle(edge: .topRight)
                .position(x: item.size.width, y: 0)
                .gesture(resizeGesture(edge: .topRight))

            FloatingResizeHandle(edge: .bottomLeft)
                .position(x: 0, y: item.size.height)
                .gesture(resizeGesture(edge: .bottomLeft))

            FloatingResizeHandle(edge: .bottomRight)
                .position(x: item.size.width, y: item.size.height)
                .gesture(resizeGesture(edge: .bottomRight))

            FloatingResizeHandle(edge: .top)
                .position(x: item.size.width / 2, y: 0)
                .gesture(resizeGesture(edge: .top))

            FloatingResizeHandle(edge: .bottom)
                .position(x: item.size.width / 2, y: item.size.height)
                .gesture(resizeGesture(edge: .bottom))

            FloatingResizeHandle(edge: .left)
                .position(x: 0, y: item.size.height / 2)
                .gesture(resizeGesture(edge: .left))

            FloatingResizeHandle(edge: .right)
                .position(x: item.size.width, y: item.size.height / 2)
                .gesture(resizeGesture(edge: .right))
        }
        .frame(width: item.size.width, height: item.size.height)
    }

    private func resizeGesture(edge: FloatingResizeEdge) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isResizing {
                    isResizing = true
                    initialSize = item.size
                    initialPosition = item.position
                    onBringToFront()
                }

                let delta = value.translation
                var newSize = initialSize
                var newPosition = initialPosition

                switch edge {
                case .left, .topLeft, .bottomLeft:
                    let widthDelta = -delta.width
                    let newWidth = max(minSize.width, initialSize.width + widthDelta)
                    let actualWidthChange = newWidth - initialSize.width
                    newSize.width = newWidth
                    newPosition.x = initialPosition.x - actualWidthChange

                case .right, .topRight, .bottomRight:
                    newSize.width = max(minSize.width, initialSize.width + delta.width)

                default:
                    break
                }

                switch edge {
                case .top, .topLeft, .topRight:
                    let heightDelta = -delta.height
                    let newHeight = max(minSize.height, initialSize.height + heightDelta)
                    let actualHeightChange = newHeight - initialSize.height
                    newSize.height = newHeight
                    newPosition.y = initialPosition.y - actualHeightChange

                case .bottom, .bottomLeft, .bottomRight:
                    newSize.height = max(minSize.height, initialSize.height + delta.height)

                default:
                    break
                }

                newPosition.x = clampX(newPosition.x)
                newPosition.y = clampY(newPosition.y)
                onUpdateSize(newSize)
                onUpdatePosition(newPosition)
            }
            .onEnded { _ in
                isResizing = false
            }
    }
}

struct FloatingWindowPositionModifier<Item: FloatingWindowItemProtocol>: ViewModifier {
    var item: Item
    let containerSize: CGSize

    func body(content: Content) -> some View {
        content.position(calculatedPosition)
    }

    private var calculatedPosition: CGPoint {
        if item.isMaximized {
            return CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        }

        return CGPoint(
            x: item.position.x + item.size.width / 2,
            y: item.position.y + item.size.height / 2
        )
    }
}

private enum FloatingResizeEdge {
    case top, bottom, left, right
    case topLeft, topRight, bottomLeft, bottomRight

    var cursor: NSCursor {
        switch self {
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right:
            return .resizeLeftRight
        case .topLeft, .bottomRight, .topRight, .bottomLeft:
            return .crosshair
        }
    }
}

private struct FloatingResizeHandle: View {
    let edge: FloatingResizeEdge

    private let handleSize: CGFloat = 12

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: frameSize.width, height: frameSize.height)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    edge.cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var frameSize: CGSize {
        switch edge {
        case .top, .bottom:
            return CGSize(width: 40, height: handleSize)
        case .left, .right:
            return CGSize(width: handleSize, height: 40)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return CGSize(width: handleSize, height: handleSize)
        }
    }
}

private struct TrafficLightButton: View {
    let color: Color
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    private let size: CGFloat = 12

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)

                if isHovered {
                    Image(systemName: icon)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(Color(nsColor: .textBackgroundColor).opacity(0.8))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}
