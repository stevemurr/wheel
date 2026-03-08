import Foundation
import SwiftUI

@MainActor
@Observable
final class NoteWindowItem: @MainActor FloatingWindowItemProtocol {
    let id = UUID()
    let createdAt = Date()

    var noteID: UUID
    var title: String
    var position: CGPoint
    var size: CGSize
    var isMinimized: Bool = false
    var isMaximized: Bool = false
    var zIndex: Int = 0
    var preMaximizePosition: CGPoint?
    var preMaximizeSize: CGSize?

    init(noteID: UUID, title: String, position: CGPoint, size: CGSize) {
        self.noteID = noteID
        self.title = title
        self.position = position
        self.size = size
    }
}

@MainActor
@Observable
final class NoteWindowState {
    var window: NoteWindowItem?
    @ObservationIgnored var containerSize: CGSize = .zero

    private let defaultSize = CGSize(width: 560, height: 720)
    private let margin: CGFloat = 28

    func open(note: NoteRecord) {
        if let window {
            window.noteID = note.id
            window.title = note.displayTitle
            return
        }

        let size = defaultSize
        let position = defaultPosition(for: size)
        window = NoteWindowItem(
            noteID: note.id,
            title: note.displayTitle,
            position: position,
            size: size
        )
    }

    func close() {
        window = nil
    }

    func bringToFront() {}

    func updatePosition(_ position: CGPoint) {
        guard let window else { return }
        window.position = position
        if window.isMaximized {
            window.isMaximized = false
        }
    }

    func updateSize(_ size: CGSize) {
        guard let window else { return }
        window.size = size
        if window.isMaximized {
            window.isMaximized = false
        }
    }

    func minimize() {
        window?.isMinimized.toggle()
    }

    func toggleMaximize() {
        guard let window else { return }

        if window.isMaximized {
            if let prePosition = window.preMaximizePosition,
               let preSize = window.preMaximizeSize {
                window.position = prePosition
                window.size = preSize
            }
            window.isMaximized = false
            return
        }

        window.preMaximizePosition = window.position
        window.preMaximizeSize = window.size
        window.position = .zero
        if containerSize.width > 0, containerSize.height > 0 {
            window.size = containerSize
        }
        window.isMaximized = true
    }

    func updateTitle(_ title: String) {
        window?.title = title
    }

    private func defaultPosition(for size: CGSize) -> CGPoint {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return CGPoint(x: 120, y: 40)
        }

        return CGPoint(
            x: max(margin, containerSize.width - size.width - margin),
            y: margin
        )
    }
}
